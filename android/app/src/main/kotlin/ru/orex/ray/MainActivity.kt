package ru.orex.ray

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "OrexRay"
        private const val METHOD_CHANNEL = "ru.orex.ray/tunnel"
        private const val EVENT_CHANNEL = "ru.orex.ray/tunnel_events"
        private const val SECURE_CHANNEL = "ru.orex.ray/secure_storage"
        private const val FILE_EXPORT_CHANNEL = "ru.orex.ray/file_export"
        private const val VPN_PERMISSION_REQUEST = 7711
        private const val NOTIFICATION_PERMISSION_REQUEST = 7712
        private const val FILE_EXPORT_REQUEST = 7713
        private const val MODE_VPN = "vpn_tun"
        private const val MODE_LOCAL_PROXY = "local_proxy"
    }

    private data class StartRequest(
        val config: String,
        val mode: String,
        val targetId: String?,
        val targetName: String,
        val latencyMs: Int?,
        val pingStatus: String,
        val latencyProbeUrl: String,
        val statsOutboundTags: List<String>,
        val mtu: Int,
        val dnsServers: List<String>,
        val socksPort: Int,
        val httpPort: Int,
        val localProxyInVpn: Boolean,
        val statsIntervalSeconds: Int,
        val showNotificationSpeed: Boolean,
        val showNotificationPing: Boolean,
        val statsUiActive: Boolean,
        val restartServiceOnKill: Boolean,
        val appRoutingMode: String,
        val appPackages: List<String>,
    )

    private var pendingStart: StartRequest? = null
    private var pendingFileExportResult: MethodChannel.Result? = null
    private var pendingFileExportContent: String? = null
    private val secureStore by lazy { AndroidSecureStore(applicationContext) }
    private val packageWorker = Executors.newFixedThreadPool(2)

    @Volatile
    private var activityDestroyed = false

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
                            result.error(
                                "invalid_mode",
                                "Unsupported Android mode: $mode",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val request = StartRequest(
                            config = config,
                            mode = mode,
                            targetId = call.argument<String>("targetId")
                                ?.trim()
                                ?.takeIf { it.isNotEmpty() },
                            targetName = call.argument<String>("targetName")
                                ?.trim()
                                ?.takeIf { it.isNotEmpty() }
                                ?: "OrexRay",
                            latencyMs = call.argument<Int>("latencyMs")
                                ?.takeIf { it >= 0 },
                            pingStatus = normalizePingStatus(
                                call.argument<String>("pingStatus"),
                                call.argument<Int>("latencyMs")?.takeIf { it >= 0 },
                            ),
                            latencyProbeUrl = normalizeLatencyProbeUrl(
                                call.argument<String>("latencyProbeUrl"),
                            ),
                            statsOutboundTags = call.argument<List<String>>(
                                "statsOutboundTags",
                            )
                                ?.map { it.trim() }
                                ?.filter {
                                    it == "proxy" || it == "fallback-proxy" || it.matches(Regex("proxy-\\d+"))
                                }
                                ?.distinct()
                                .orEmpty()
                                .ifEmpty { listOf("proxy") },
                            mtu = (call.argument<Int>("mtu") ?: 1500)
                                .coerceIn(1280, 9000),
                            dnsServers = call.argument<List<String>>("dnsServers")
                                ?.filter { it.isNotBlank() }
                                ?.take(4)
                                .orEmpty(),
                            socksPort = (call.argument<Int>("socksPort") ?: 20808)
                                .coerceIn(1, 65535),
                            httpPort = (call.argument<Int>("httpPort") ?: 20809)
                                .coerceIn(1, 65535),
                            localProxyInVpn =
                                call.argument<Boolean>("localProxyInVpn") ?: true,
                            statsIntervalSeconds = (
                                call.argument<Int>("statsIntervalSeconds") ?: 2
                            ).let { if (it in setOf(1, 2, 5, 10)) it else 2 },
                            showNotificationSpeed =
                                call.argument<Boolean>("showNotificationSpeed") ?: true,
                            showNotificationPing =
                                call.argument<Boolean>("showNotificationPing") ?: true,
                            statsUiActive =
                                call.argument<Boolean>("statsUiActive") ?: false,
                            restartServiceOnKill =
                                call.argument<Boolean>("restartServiceOnKill") ?: true,
                            appRoutingMode =
                                call.argument<String>("appRoutingMode") ?: "all",
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

                    "updateTargetMetadata" -> {
                        runCatching {
                            updateTargetMetadata(
                                targetId = call.argument<String>("targetId"),
                                targetName = call.argument<String>("targetName"),
                                latencyMs = call.argument<Int>("latencyMs"),
                                pingStatus = call.argument<String>("pingStatus"),
                                latencyProbeUrl = call.argument<String>("latencyProbeUrl"),
                            )
                        }
                            .onSuccess { result.success(null) }
                            .onFailure { error ->
                                result.error(
                                    "metadata_update_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                    }

                    "updateRuntimeSettings" -> {
                        runCatching {
                            updateRuntimeSettings(
                                statsIntervalSeconds = call.argument<Int>("statsIntervalSeconds")
                                    ?: 2,
                                showNotificationSpeed =
                                    call.argument<Boolean>("showNotificationSpeed") ?: true,
                                showNotificationPing =
                                    call.argument<Boolean>("showNotificationPing") ?: true,
                            )
                        }
                            .onSuccess { result.success(null) }
                            .onFailure { error ->
                                result.error(
                                    "runtime_settings_update_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                    }

                    "setStatsUiActive" -> {
                        runCatching {
                            setStatsUiActive(call.arguments as? Boolean ?: false)
                        }
                            .onSuccess { result.success(null) }
                            .onFailure { error ->
                                result.error(
                                    "stats_consumer_update_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                    }

                    "status" -> result.success(OrexRayVpnService.runtimeState(this))
                    "setAutoConnectOnBoot" -> {
                        OrexRayStartupStore.setAutoConnectOnBoot(
                            this,
                            call.arguments as? Boolean ?: false,
                        )
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        runCatching { openNotificationSettings() }
                            .onSuccess { result.success(null) }
                            .onFailure { error ->
                                result.error(
                                    "notification_settings_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                    }
                    "diagnostics" -> result.success(OrexRayDiagnosticsStore.snapshot())
                    "assetDirectory" -> result.success(
                        File(filesDir, "xray").apply { mkdirs() }.absolutePath,
                    )
                    "listApps" -> loadAppsAsync(result)
                    "loadAppIcon" -> {
                        val packageName = call.argument<String>("packageName")?.trim().orEmpty()
                        if (packageName.isEmpty()) {
                            result.error("invalid_package", "Package name is empty", null)
                        } else {
                            loadAppIconAsync(packageName, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink,
                ) {
                    OrexRayTunnelEvents.attach(applicationContext, events)
                }

                override fun onCancel(arguments: Any?) {
                    OrexRayTunnelEvents.detach()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                runCatching {
                    val key = call.argument<String>("key")?.trim().orEmpty()
                    require(key.isNotEmpty()) { "Secure storage key is empty" }
                    when (call.method) {
                        "read" -> result.success(secureStore.read(key))
                        "write" -> {
                            val value = call.argument<String>("value")
                                ?: error("Secure storage value is missing")
                            secureStore.write(key, value)
                            result.success(null)
                        }
                        "delete" -> {
                            secureStore.delete(key)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }.onFailure { error ->
                    Log.e(TAG, "Secure storage operation failed", error)
                    result.error(
                        "secure_storage_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveJson" -> {
                        val fileName = call.argument<String>("fileName")
                            ?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: "orexray-xray.json"
                        val content = call.argument<String>("content")
                        if (content == null) {
                            result.error("invalid_content", "JSON content is missing", null)
                            return@setMethodCallHandler
                        }
                        if (pendingFileExportResult != null) {
                            result.error("export_busy", "Another file export is active", null)
                            return@setMethodCallHandler
                        }
                        pendingFileExportResult = result
                        pendingFileExportContent = content
                        runCatching {
                            startActivityForResult(
                                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/json"
                                    putExtra(Intent.EXTRA_TITLE, fileName)
                                },
                                FILE_EXPORT_REQUEST,
                            )
                        }.onFailure { error ->
                            pendingFileExportResult = null
                            pendingFileExportContent = null
                            result.error(
                                "export_failed",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun loadAppsAsync(result: MethodChannel.Result) {
        if (activityDestroyed) return
        packageWorker.execute {
            runCatching { listInstalledApps() }
                .onSuccess { apps ->
                    if (!activityDestroyed) {
                        runOnUiThread {
                            if (!activityDestroyed) result.success(apps)
                        }
                    }
                }
                .onFailure { error ->
                    Log.e(TAG, "Could not list installed apps", error)
                    if (!activityDestroyed) runOnUiThread {
                        if (activityDestroyed) return@runOnUiThread
                        result.error(
                            "list_apps_failed",
                            error.message ?: error.javaClass.simpleName,
                            null,
                        )
                    }
                }
        }
    }

    @Suppress("DEPRECATION")
    private fun listInstalledApps(): List<Map<String, Any?>> {
        val launcherPackages = packageManager
            .queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
                0,
            )
            .mapNotNull { it.activityInfo?.packageName }
            .toSet()

        return packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            .asSequence()
            .filter { it.packageName != packageName }
            .map { info ->
                val label = runCatching {
                    packageManager.getApplicationLabel(info).toString()
                }
                    .getOrDefault(info.packageName)
                    .trim()
                    .ifEmpty { info.packageName }
                val system =
                    (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                        (info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                mapOf(
                    "packageName" to info.packageName,
                    "label" to label,
                    "isSystem" to system,
                    "hasLauncher" to launcherPackages.contains(info.packageName),
                )
            }
            .sortedWith(
                compareBy<Map<String, Any?>> {
                    (it["label"] as? String).orEmpty().lowercase()
                }.thenBy { (it["packageName"] as? String).orEmpty() },
            )
            .toList()
    }

    private fun loadAppIconAsync(packageName: String, result: MethodChannel.Result) {
        if (activityDestroyed) return
        packageWorker.execute {
            val encoded = encodeAppIcon(packageName)
            if (!activityDestroyed) {
                runOnUiThread {
                    if (!activityDestroyed) result.success(encoded)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun encodeAppIcon(packageName: String): String? {
        return runCatching {
            val info = packageManager.getApplicationInfo(packageName, 0)
            val size = (44 * resources.displayMetrics.density)
                .toInt()
                .coerceIn(48, 96)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val drawable = info.loadIcon(packageManager)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 90, output)
            bitmap.recycle()
            Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
        }.getOrNull()
    }

    override fun onDestroy() {
        activityDestroyed = true
        pendingFileExportResult?.error(
            "activity_destroyed",
            "Activity was destroyed during file export",
            null,
        )
        pendingFileExportResult = null
        pendingFileExportContent = null
        packageWorker.shutdownNow()
        super.onDestroy()
    }

    private fun debugInfo(message: String) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) Log.i(TAG, message)
    }

    private fun debugLog(message: String) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) Log.d(TAG, message)
    }

    private fun startRequestedMode(request: StartRequest) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
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
                this,
                OrexRayTunnelEvents.event(
                    status = "connecting",
                    mode = request.mode,
                    targetId = request.targetId,
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

    @Deprecated("The platform callback is required for VPN permission and document export")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_EXPORT_REQUEST) {
            val callback = pendingFileExportResult ?: return
            val content = pendingFileExportContent
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pendingFileExportResult = null
                pendingFileExportContent = null
                callback.success(null)
                return
            }
            val uri = data.data!!
            if (content == null) {
                pendingFileExportResult = null
                pendingFileExportContent = null
                callback.error("export_failed", "JSON content is missing", null)
                return
            }

            // Release the potentially large JSON string, but keep the result pending
            // until the worker finishes. This both prevents overlapping exports and lets
            // onDestroy() resolve the Dart Future if the Activity disappears mid-write.
            pendingFileExportContent = null
            runCatching {
                packageWorker.execute {
                    val writeResult = runCatching {
                        contentResolver.openOutputStream(uri, "wt")?.use { output ->
                            output.write(content.toByteArray(Charsets.UTF_8))
                            output.flush()
                        } ?: error("Could not open selected document")
                    }
                    runOnUiThread {
                        // onDestroy() may already have resolved and cleared this callback.
                        if (pendingFileExportResult !== callback) return@runOnUiThread
                        pendingFileExportResult = null
                        writeResult.onSuccess {
                            callback.success(uri.toString())
                        }.onFailure { error ->
                            Log.e(TAG, "Could not export JSON", error)
                            callback.error(
                                "export_failed",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                }
            }.onFailure { error ->
                if (pendingFileExportResult === callback) {
                    pendingFileExportResult = null
                }
                Log.e(TAG, "Could not schedule JSON export", error)
                callback.error(
                    "export_failed",
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
            return
        }
        if (requestCode != VPN_PERMISSION_REQUEST) return

        val request = pendingStart
        pendingStart = null
        if (resultCode == Activity.RESULT_OK && request != null) {
            runCatching { startCoreService(request) }
                .onFailure { error ->
                    Log.e(TAG, "Could not start VPN service after permission", error)
                    OrexRayTunnelEvents.emit(
                        this,
                        OrexRayTunnelEvents.event(
                            status = "error",
                            mode = request.mode,
                            errorMessage = error.message ?: error.javaClass.simpleName,
                        ),
                    )
                }
        } else {
            OrexRayTunnelEvents.emit(
                this,
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
            .putExtra(OrexRayVpnService.EXTRA_TARGET_ID, request.targetId)
            .putExtra(OrexRayVpnService.EXTRA_TARGET_NAME, request.targetName)
            .putExtra(OrexRayVpnService.EXTRA_LATENCY_MS, request.latencyMs ?: -1)
            .putExtra(OrexRayVpnService.EXTRA_PING_STATUS, request.pingStatus)
            .putExtra(
                OrexRayVpnService.EXTRA_LATENCY_PROBE_URL,
                request.latencyProbeUrl,
            )
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
                OrexRayVpnService.EXTRA_LOCAL_PROXY_IN_VPN,
                request.localProxyInVpn,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS,
                request.statsIntervalSeconds,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED,
                request.showNotificationSpeed,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_PING,
                request.showNotificationPing,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_STATS_UI_ACTIVE,
                request.statsUiActive,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_RESTART_SERVICE,
                request.restartServiceOnKill,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_APP_ROUTING_MODE,
                request.appRoutingMode,
            )
            .putStringArrayListExtra(
                OrexRayVpnService.EXTRA_APP_PACKAGES,
                ArrayList(request.appPackages),
            )

        debugInfo("Starting core service in mode=${request.mode}")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun updateTargetMetadata(
        targetId: String?,
        targetName: String?,
        latencyMs: Int?,
        pingStatus: String?,
        latencyProbeUrl: String?,
    ) {
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_UPDATE_METADATA)
            .putExtra(
                OrexRayVpnService.EXTRA_TARGET_ID,
                targetId?.trim().orEmpty(),
            )
            .putExtra(
                OrexRayVpnService.EXTRA_TARGET_NAME,
                targetName?.trim().orEmpty(),
            )
            .putExtra(OrexRayVpnService.EXTRA_LATENCY_MS, latencyMs ?: -1)
            .putExtra(
                OrexRayVpnService.EXTRA_PING_STATUS,
                normalizePingStatus(pingStatus, latencyMs),
            )
            .putExtra(
                OrexRayVpnService.EXTRA_LATENCY_PROBE_URL,
                normalizeLatencyProbeUrl(latencyProbeUrl),
            )
        startService(intent)
    }

    private fun normalizePingStatus(value: String?, latencyMs: Int?): String =
        when (value?.trim()?.lowercase()) {
            "success" -> if (latencyMs != null && latencyMs >= 0) "success" else "unknown"
            "timeout" -> "timeout"
            "unavailable" -> "unavailable"
            else -> if (latencyMs != null && latencyMs >= 0) "success" else "unknown"
        }

    private fun normalizeLatencyProbeUrl(value: String?): String {
        val normalized = value?.trim().orEmpty()
        return if (normalized.startsWith("https://") || normalized.startsWith("http://")) {
            normalized
        } else {
            "https://cloudflare.com/cdn-cgi/trace"
        }
    }

    private fun updateRuntimeSettings(
        statsIntervalSeconds: Int,
        showNotificationSpeed: Boolean,
        showNotificationPing: Boolean,
    ) {
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_UPDATE_RUNTIME_SETTINGS)
            .putExtra(
                OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS,
                statsIntervalSeconds,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED,
                showNotificationSpeed,
            )
            .putExtra(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_PING,
                showNotificationPing,
            )
        startService(intent)
    }

    private fun setStatsUiActive(active: Boolean) {
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_SET_STATS_UI_ACTIVE)
            .putExtra(OrexRayVpnService.EXTRA_STATS_UI_ACTIVE, active)
        startService(intent)
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(
                    Settings.EXTRA_CHANNEL_ID,
                    OrexRayVpnService.NOTIFICATION_CHANNEL_ID,
                )
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        startActivity(intent)
    }

    private fun stopCoreService() {
        pendingStart = null
        val intent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_STOP)
        startService(intent)
    }
}
