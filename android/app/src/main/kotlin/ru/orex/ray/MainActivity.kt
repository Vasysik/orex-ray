package ru.orex.ray

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "OrexRay"
        private const val METHOD_CHANNEL = "ru.orex.ray/tunnel"
        private const val EVENT_CHANNEL = "ru.orex.ray/tunnel_events"
        private const val VPN_PERMISSION_REQUEST = 7711
        private const val MODE_VPN = "vpn_tun"
        private const val MODE_LOCAL_PROXY = "local_proxy"
    }

    private var pendingConfig: String? = null
    private var pendingMode: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val config = call.argument<String>("config")
                        val mode = call.argument<String>("mode") ?: MODE_VPN
                        if (config.isNullOrBlank()) {
                            result.error("invalid_config", "Xray config is empty", null)
                            return@setMethodCallHandler
                        }
                        if (mode != MODE_VPN && mode != MODE_LOCAL_PROXY) {
                            result.error("invalid_mode", "Unsupported Android mode: $mode", null)
                            return@setMethodCallHandler
                        }

                        runCatching { startRequestedMode(config, mode) }
                            .onSuccess { result.success(null) }
                            .onFailure { error ->
                                Log.e(TAG, "Could not start OrexRay", error)
                                result.error(
                                    "start_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                    }

                    "stop" -> {
                        runCatching { stopCoreService() }
                            .onSuccess { result.success(null) }
                            .onFailure { error ->
                                Log.e(TAG, "Could not stop OrexRay", error)
                                result.error(
                                    "stop_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                    }

                    "status" -> result.success(OrexRayTunnelEvents.lastEvent)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    OrexRayTunnelEvents.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    OrexRayTunnelEvents.detach()
                }
            })
    }

    private fun startRequestedMode(config: String, mode: String) {
        if (mode == MODE_LOCAL_PROXY) {
            pendingConfig = null
            pendingMode = null
            startCoreService(config, mode)
            return
        }

        pendingConfig = config
        pendingMode = mode
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            OrexRayTunnelEvents.emit(
                OrexRayTunnelEvents.event(
                    status = "connecting",
                    mode = mode,
                    message = "Подтверди системное разрешение VPN",
                ),
            )
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }

        pendingConfig = null
        pendingMode = null
        startCoreService(config, mode)
    }

    @Deprecated("The platform callback is required for the VPN permission activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return

        val config = pendingConfig
        val mode = pendingMode ?: MODE_VPN
        pendingConfig = null
        pendingMode = null

        if (resultCode == Activity.RESULT_OK && !config.isNullOrBlank()) {
            runCatching { startCoreService(config, mode) }
                .onFailure { error ->
                    Log.e(TAG, "Could not start VPN service after permission", error)
                    OrexRayTunnelEvents.emit(
                        OrexRayTunnelEvents.event(
                            status = "error",
                            mode = mode,
                            errorMessage = error.message ?: error.javaClass.simpleName,
                        ),
                    )
                }
        } else {
            OrexRayTunnelEvents.emit(
                OrexRayTunnelEvents.event(
                    status = "error",
                    mode = mode,
                    errorMessage = "Разрешение VPN не выдано",
                ),
            )
        }
    }

    private fun startCoreService(config: String, mode: String) {
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_START)
            .putExtra(OrexRayVpnService.EXTRA_CONFIG, config)
            .putExtra(OrexRayVpnService.EXTRA_MODE, mode)

        Log.i(TAG, "Starting core service in mode=$mode")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopCoreService() {
        pendingConfig = null
        pendingMode = null
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_STOP)
        startService(intent)
    }
}
