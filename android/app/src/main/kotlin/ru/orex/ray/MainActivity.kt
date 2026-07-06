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
        private const val DEFAULT_MTU = 1500
        private const val DEFAULT_SOCKS_PORT = 20808
        private const val DEFAULT_HTTP_PORT = 20809
    }

    private var pendingConfig: String? = null
    private var pendingMode: String? = null
    private var pendingMtu = DEFAULT_MTU
    private var pendingDnsServers = listOf("1.1.1.1", "8.8.8.8")
    private var pendingSocksPort = DEFAULT_SOCKS_PORT
    private var pendingHttpPort = DEFAULT_HTTP_PORT

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val config = call.argument<String>("config")
                        val mode = call.argument<String>("mode") ?: MODE_VPN
                        val mtu = call.argument<Int>("mtu") ?: DEFAULT_MTU
                        val dnsServers = call.argument<List<String>>("dnsServers")
                            ?.filter { it.isNotBlank() }
                            ?.take(4)
                            .orEmpty()
                        val socksPort = call.argument<Int>("socksPort") ?: DEFAULT_SOCKS_PORT
                        val httpPort = call.argument<Int>("httpPort") ?: DEFAULT_HTTP_PORT

                        if (config.isNullOrBlank()) {
                            result.error("invalid_config", "Xray config is empty", null)
                            return@setMethodCallHandler
                        }
                        if (mode != MODE_VPN && mode != MODE_LOCAL_PROXY) {
                            result.error("invalid_mode", "Unsupported Android mode: $mode", null)
                            return@setMethodCallHandler
                        }

                        runCatching {
                            startRequestedMode(
                                config = config,
                                mode = mode,
                                mtu = mtu.coerceIn(1280, 9000),
                                dnsServers = dnsServers.ifEmpty { listOf("1.1.1.1", "8.8.8.8") },
                                socksPort = socksPort.coerceIn(1, 65535),
                                httpPort = httpPort.coerceIn(1, 65535),
                            )
                        }
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

    private fun startRequestedMode(
        config: String,
        mode: String,
        mtu: Int,
        dnsServers: List<String>,
        socksPort: Int,
        httpPort: Int,
    ) {
        if (mode == MODE_LOCAL_PROXY) {
            clearPendingStart()
            startCoreService(config, mode, mtu, dnsServers, socksPort, httpPort)
            return
        }

        pendingConfig = config
        pendingMode = mode
        pendingMtu = mtu
        pendingDnsServers = dnsServers
        pendingSocksPort = socksPort
        pendingHttpPort = httpPort

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

        val configToStart = pendingConfig ?: return
        val modeToStart = pendingMode ?: MODE_VPN
        val mtuToStart = pendingMtu
        val dnsToStart = pendingDnsServers
        val socksToStart = pendingSocksPort
        val httpToStart = pendingHttpPort
        clearPendingStart()
        startCoreService(
            configToStart,
            modeToStart,
            mtuToStart,
            dnsToStart,
            socksToStart,
            httpToStart,
        )
    }

    @Deprecated("The platform callback is required for the VPN permission activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return

        val config = pendingConfig
        val mode = pendingMode ?: MODE_VPN
        val mtu = pendingMtu
        val dnsServers = pendingDnsServers
        val socksPort = pendingSocksPort
        val httpPort = pendingHttpPort
        clearPendingStart()

        if (resultCode == Activity.RESULT_OK && !config.isNullOrBlank()) {
            runCatching {
                startCoreService(config, mode, mtu, dnsServers, socksPort, httpPort)
            }.onFailure { error ->
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

    private fun startCoreService(
        config: String,
        mode: String,
        mtu: Int,
        dnsServers: List<String>,
        socksPort: Int,
        httpPort: Int,
    ) {
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_START)
            .putExtra(OrexRayVpnService.EXTRA_CONFIG, config)
            .putExtra(OrexRayVpnService.EXTRA_MODE, mode)
            .putExtra(OrexRayVpnService.EXTRA_MTU, mtu)
            .putStringArrayListExtra(OrexRayVpnService.EXTRA_DNS_SERVERS, ArrayList(dnsServers))
            .putExtra(OrexRayVpnService.EXTRA_SOCKS_PORT, socksPort)
            .putExtra(OrexRayVpnService.EXTRA_HTTP_PORT, httpPort)

        Log.i(TAG, "Starting core service in mode=$mode")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopCoreService() {
        clearPendingStart()
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_STOP)
        startService(intent)
    }

    private fun clearPendingStart() {
        pendingConfig = null
        pendingMode = null
        pendingMtu = DEFAULT_MTU
        pendingDnsServers = listOf("1.1.1.1", "8.8.8.8")
        pendingSocksPort = DEFAULT_SOCKS_PORT
        pendingHttpPort = DEFAULT_HTTP_PORT
    }
}
