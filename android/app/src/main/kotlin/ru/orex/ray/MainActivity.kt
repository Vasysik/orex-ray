package ru.orex.ray

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "OrexRay"
        private const val METHOD_CHANNEL = "ru.orex.ray/tunnel"
        private const val EVENT_CHANNEL = "ru.orex.ray/tunnel_events"
        private const val VPN_PERMISSION_REQUEST = 7711
        private const val NOTIFICATION_PERMISSION_REQUEST = 7712
        private const val MODE_VPN = "vpn_tun"
        private const val MODE_LOCAL_PROXY = "local_proxy"
    }

    private data class StartRequest(
        val config: String,
        val mode: String,
        val targetName: String,
        val statsOutboundTags: List<String>,
        val mtu: Int,
        val dnsServers: List<String>,
        val socksPort: Int,
        val httpPort: Int,
        val statsIntervalSeconds: Int,
        val showNotificationSpeed: Boolean,
        val restartServiceOnKill: Boolean,
        val appRoutingMode: String,
        val appPackages: List<String>,
    )

    private var pendingStart: StartRequest? = null

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

                        val request = StartRequest(
                            config = config,
                            mode = mode,
                            targetName = call.argument<String>("targetName")
                                ?.trim()
                                ?.takeIf { it.isNotEmpty() }
                                ?: "OrexRay",
                            statsOutboundTags = call.argument<List<String>>("statsOutboundTags")
                                ?.map { it.trim() }
                                ?.filter { it == "proxy" || it.matches(Regex("proxy-\\d+")) }
                                ?.distinct()
                                .orEmpty()
                                .ifEmpty { listOf("proxy") },
                            mtu = (call.argument<Int>("mtu") ?: 1500).coerceIn(1280, 9000),
                            dnsServers = call.argument<List<String>>("dnsServers")
                                ?.filter { it.isNotBlank() }
                                ?.take(4)
                                .orEmpty()
                                .ifEmpty { listOf("1.1.1.1", "8.8.8.8") },
                            socksPort = (call.argument<Int>("socksPort") ?: 20808)
                                .coerceIn(1, 65535),
                            httpPort = (call.argument<Int>("httpPort") ?: 20809)
                                .coerceIn(1, 65535),
                            statsIntervalSeconds = (call.argument<Int>("statsIntervalSeconds") ?: 2)
                                .let { if (it in setOf(1, 2, 5, 10)) it else 2 },
                            showNotificationSpeed =
                                call.argument<Boolean>("showNotificationSpeed") ?: true,
                            restartServiceOnKill =
                                call.argument<Boolean>("restartServiceOnKill") ?: true,
                            appRoutingMode = call.argument<String>("appRoutingMode") ?: "all",
                            appPackages = call.argument<List<String>>("appPackages")
                                ?.filter { it.isNotBlank() }
                                ?.distinct()
                                .orEmpty(),
                        )

                        runCatching { startRequestedMode(request) }
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
                    "assetDirectory" -> result.success(
                        File(filesDir, "xray").apply { mkdirs() }.absolutePath,
                    )
                    "listApps" -> result.success(listLaunchableApps())
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

    private fun listLaunchableApps(): List<Map<String, String>> {
        val launchIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(launchIntent, 0)
            .mapNotNull { info ->
                val packageName = info.activityInfo?.packageName?.trim().orEmpty()
                if (packageName.isEmpty() || packageName == this.packageName) return@mapNotNull null
                val label = runCatching { info.loadLabel(packageManager).toString() }
                    .getOrDefault(packageName)
                    .trim()
                    .ifEmpty { packageName }
                mapOf("packageName" to packageName, "label" to label)
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
    }

    private fun startRequestedMode(request: StartRequest) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            pendingStart = request
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
            return
        }
        continueStart(request)
    }

    private fun continueStart(request: StartRequest) {
        if (request.mode == MODE_LOCAL_PROXY) {
            pendingStart = null
            startCoreService(request)
            return
        }

        pendingStart = request
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            OrexRayTunnelEvents.emit(
                OrexRayTunnelEvents.event(
                    status = "connecting",
                    mode = request.mode,
                    message = "Подтверди системное разрешение VPN",
                ),
            )
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }

        pendingStart = null
        startCoreService(request)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val request = pendingStart ?: return
        pendingStart = null
        continueStart(request)
    }

    @Deprecated("The platform callback is required for the VPN permission activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return

        val request = pendingStart
        pendingStart = null
        if (resultCode == Activity.RESULT_OK && request != null) {
            runCatching { startCoreService(request) }
                .onFailure { error ->
                    Log.e(TAG, "Could not start VPN service after permission", error)
                    OrexRayTunnelEvents.emit(
                        OrexRayTunnelEvents.event(
                            status = "error",
                            mode = request.mode,
                            errorMessage = error.message ?: error.javaClass.simpleName,
                        ),
                    )
                }
        } else {
            OrexRayTunnelEvents.emit(
                OrexRayTunnelEvents.event(
                    status = "error",
                    mode = request?.mode ?: MODE_VPN,
                    errorMessage = "Разрешение VPN не выдано",
                ),
            )
        }
    }

    private fun startCoreService(request: StartRequest) {
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_START)
            .putExtra(OrexRayVpnService.EXTRA_CONFIG, request.config)
            .putExtra(OrexRayVpnService.EXTRA_MODE, request.mode)
            .putExtra(OrexRayVpnService.EXTRA_TARGET_NAME, request.targetName)
            .putStringArrayListExtra(
                OrexRayVpnService.EXTRA_STATS_OUTBOUND_TAGS,
                ArrayList(request.statsOutboundTags),
            )
            .putExtra(OrexRayVpnService.EXTRA_MTU, request.mtu)
            .putStringArrayListExtra(
                OrexRayVpnService.EXTRA_DNS_SERVERS,
                ArrayList(request.dnsServers),
            )
            .putExtra(OrexRayVpnService.EXTRA_SOCKS_PORT, request.socksPort)
            .putExtra(OrexRayVpnService.EXTRA_HTTP_PORT, request.httpPort)
            .putExtra(
                OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS,
                request.statsIntervalSeconds,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED,
                request.showNotificationSpeed,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_RESTART_SERVICE,
                request.restartServiceOnKill,
            )
            .putExtra(OrexRayVpnService.EXTRA_APP_ROUTING_MODE, request.appRoutingMode)
            .putStringArrayListExtra(
                OrexRayVpnService.EXTRA_APP_PACKAGES,
                ArrayList(request.appPackages),
            )

        Log.i(TAG, "Starting core service in mode=${request.mode}")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopCoreService() {
        pendingStart = null
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_STOP)
        startService(intent)
    }
}
