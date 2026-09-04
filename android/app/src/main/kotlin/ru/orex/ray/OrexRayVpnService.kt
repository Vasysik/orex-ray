package ru.orex.ray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.ResultReceiver
import android.os.SystemClock
import android.util.Log
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.SocketTimeoutException
import java.net.URL
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.max

class OrexRayVpnService : VpnService(), CoreCallbackHandler {
    companion object {
        const val ACTION_START = "ru.orex.ray.action.START"
        const val ACTION_STOP = "ru.orex.ray.action.STOP"
        const val ACTION_UPDATE_METADATA = "ru.orex.ray.action.UPDATE_METADATA"
        const val ACTION_UPDATE_RUNTIME_SETTINGS =
            "ru.orex.ray.action.UPDATE_RUNTIME_SETTINGS"
        const val ACTION_SET_STATS_UI_ACTIVE =
            "ru.orex.ray.action.SET_STATS_UI_ACTIVE"
        const val ACTION_QUERY_STATE = "ru.orex.ray.action.QUERY_STATE"
        const val ACTION_QUERY_DIAGNOSTICS = "ru.orex.ray.action.QUERY_DIAGNOSTICS"
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_MODE = "connection_mode"
        const val EXTRA_TARGET_ID = "target_id"
        const val EXTRA_TARGET_NAME = "target_name"
        const val EXTRA_LATENCY_MS = "latency_ms"
        const val EXTRA_PING_STATUS = "ping_status"
        const val EXTRA_LATENCY_PROBE_URL = "latency_probe_url"
        const val EXTRA_STATS_OUTBOUND_TAGS = "stats_outbound_tags"
        const val EXTRA_MTU = "vpn_mtu"
        const val EXTRA_DNS_SERVERS = "vpn_dns_servers"
        const val EXTRA_SOCKS_PORT = "socks_port"
        const val EXTRA_HTTP_PORT = "http_port"
        const val EXTRA_LOCAL_PROXY_IN_VPN = "local_proxy_in_vpn"
        const val EXTRA_STATS_INTERVAL_SECONDS = "stats_interval_seconds"
        const val EXTRA_PING_INTERVAL_SECONDS = "ping_interval_seconds"
        const val EXTRA_SHOW_NOTIFICATION_SPEED = "show_notification_speed"
        const val EXTRA_SHOW_NOTIFICATION_PING = "show_notification_ping"
        const val EXTRA_STATS_UI_ACTIVE = "stats_ui_active"
        const val EXTRA_RESTART_SERVICE = "restart_service"
        const val EXTRA_APP_ROUTING_MODE = "app_routing_mode"
        const val EXTRA_APP_PACKAGES = "app_packages"
        const val EXTRA_RESULT_RECEIVER = "result_receiver"

        const val MODE_VPN = "vpn_tun"
        const val MODE_LOCAL_PROXY = "local_proxy"

        private const val APP_ROUTING_ALL = "all"
        private const val APP_ROUTING_EXCLUDE = "exclude_selected"
        private const val APP_ROUTING_ONLY = "only_selected"

        private const val TAG = "OrexRay"
        const val NOTIFICATION_CHANNEL_ID = "orexray_vpn"
        private const val NOTIFICATION_ID = 7701
        private const val STOP_REQUEST_CODE = 7702
        private const val NOTIFICATION_MIN_UPDATE_MS = 5_000L
        private const val PING_INITIAL_DELAY_SECONDS = 5L
        private const val PING_TIMEOUT_MS = 6_000
        private const val DEFAULT_LATENCY_PROBE_URL =
            "https://cloudflare.com/cdn-cgi/trace"

        @Volatile
        private var activeService: OrexRayVpnService? = null

        /**
         * Quick Settings is intentionally hosted in the same :vpn process. If
         * that process was recreated after LMK/SIGKILL, a persisted connected
         * flag is stale until the VPN service itself is alive again.
         */
        fun runtimeStateInVpnProcess(context: Context): Map<String, Any?> {
            activeService?.let { return it.currentRuntimeState() }
            val persisted = OrexRayRuntimeStateStore.load(context)
            return when (persisted["status"] as? String) {
                "connected", "connecting", "disconnecting" -> OrexRayTunnelEvents.event(
                    status = "disconnected",
                    mode = persisted["mode"] as? String ?: MODE_VPN,
                )
                else -> persisted
            }
        }

    }

    private data class TrafficDelta(val download: Long, val upload: Long)
    private data class PingMeasurement(val latencyMs: Int?, val status: String)

    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val pingWorker = Executors.newSingleThreadScheduledExecutor()
    private val notificationLargeIcon by lazy {
        BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
    }
    private val secureStore by lazy {
        AndroidSecureStore(applicationContext, AndroidSecureStore.VPN_PREFS_NAME)
    }
    private var coreController: CoreController? = null
    private var vpnInterface: ParcelFileDescriptor? = null
    private var statsTask: ScheduledFuture<*>? = null
    private var watchdogTask: ScheduledFuture<*>? = null
    private var pingTask: ScheduledFuture<*>? = null
    private val watchdogRestarts = ArrayDeque<Long>()
    private var startedAtElapsedMs = 0L
    private var downloadBytes = 0L
    private var uploadBytes = 0L
    private var downloadBytesPerSecond = 0L
    private var uploadBytesPerSecond = 0L
    private var activeMode = MODE_VPN
    private var activeTargetId: String? = null
    private var activeTargetName = "OrexRay"
    @Volatile
    private var activeLatencyMs: Int? = null

    @Volatile
    private var activePingStatus = "unknown"

    @Volatile
    private var activeLatencyProbeUrl = DEFAULT_LATENCY_PROBE_URL
    private var activeStatsOutboundTags = listOf("proxy")
    private var activeMtu = 1500
    private var activeDnsServers = emptyList<String>()
    private var activeSocksPort = 20808
    private var activeHttpPort = 20809
    private var activeLocalProxyInVpn = true
    private var activeStatsIntervalSeconds = 2
    private var activePingIntervalSeconds = 60
    private var lastStatsSampleElapsedMs = 0L

    @Volatile
    private var showNotificationSpeed = true

    @Volatile
    private var showNotificationPing = true

    @Volatile
    private var statsUiActive = false
    private var restartServiceOnKill = true
    private var activeAppRoutingMode = APP_ROUTING_ALL
    private var activeAppPackages = emptyList<String>()
    private var activeStartIntent: Intent? = null
    private var lastQuickSettingsStatus: String? = null
    private var lastNotificationFingerprint: String? = null
    private var lastNotificationUpdateElapsedMs = 0L

    @Volatile
    private var stopping = false

    override fun onCreate() {
        super.onCreate()
        activeService = this
        createNotificationChannel()
        debugInfo("Core service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val commandIntent = intent ?: restoreRestartIntent() ?: run {
            stopSelf()
            return Service.START_NOT_STICKY
        }

        when (commandIntent.action) {
            ACTION_QUERY_STATE -> return handleStateQuery(commandIntent, startId)
            ACTION_QUERY_DIAGNOSTICS -> return handleDiagnosticsQuery(commandIntent, startId)

            ACTION_STOP -> {
                restartServiceOnKill = false
                clearRestartState()
                worker.execute { stopTunnel() }
                return Service.START_NOT_STICKY
            }

            ACTION_SET_STATS_UI_ACTIVE -> {
                val nextStatsUiActive = commandIntent.getBooleanExtra(
                    EXTRA_STATS_UI_ACTIVE,
                    false,
                )
                if (coreController?.isRunning != true) {
                    if (nextStatsUiActive && restartFromPersistedState { restored ->
                            restored.putExtra(EXTRA_STATS_UI_ACTIVE, true)
                        }
                    ) {
                        return Service.START_STICKY
                    }
                    stopSelf(startId)
                    return Service.START_NOT_STICKY
                }
                val consumerChanged = nextStatsUiActive != statsUiActive
                statsUiActive = nextStatsUiActive
                updateStatsLoopState(restart = consumerChanged)
                updatePingLoopState()
                if (consumerChanged && statsUiActive) {
                    // The native ping loop can continue while Flutter is in
                    // the background. Publish its latest result immediately
                    // when the UI becomes active instead of waiting for the
                    // next statistics or ping tick.
                    emitConnected()
                }
                return restartMode()
            }

            ACTION_UPDATE_RUNTIME_SETTINGS -> {
                if (coreController?.isRunning != true) {
                    if (restartFromPersistedState { restored ->
                            restored.putExtra(
                                EXTRA_STATS_INTERVAL_SECONDS,
                                commandIntent.getIntExtra(EXTRA_STATS_INTERVAL_SECONDS, 2),
                            )
                            restored.putExtra(
                                EXTRA_PING_INTERVAL_SECONDS,
                                commandIntent.getIntExtra(EXTRA_PING_INTERVAL_SECONDS, 60),
                            )
                            restored.putExtra(
                                EXTRA_SHOW_NOTIFICATION_SPEED,
                                commandIntent.getBooleanExtra(EXTRA_SHOW_NOTIFICATION_SPEED, true),
                            )
                            restored.putExtra(
                                EXTRA_SHOW_NOTIFICATION_PING,
                                commandIntent.getBooleanExtra(EXTRA_SHOW_NOTIFICATION_PING, true),
                            )
                        }
                    ) {
                        return Service.START_STICKY
                    }
                    stopSelf(startId)
                    return Service.START_NOT_STICKY
                }
                val nextInterval = commandIntent
                    .getIntExtra(EXTRA_STATS_INTERVAL_SECONDS, activeStatsIntervalSeconds)
                    .let { if (it in setOf(1, 2, 5, 10)) it else activeStatsIntervalSeconds }
                val intervalChanged = nextInterval != activeStatsIntervalSeconds
                activeStatsIntervalSeconds = nextInterval
                val nextPingInterval = commandIntent
                    .getIntExtra(EXTRA_PING_INTERVAL_SECONDS, activePingIntervalSeconds)
                    .let {
                        if (it in setOf(15, 30, 60, 120, 300)) {
                            it
                        } else {
                            activePingIntervalSeconds
                        }
                    }
                val pingIntervalChanged = nextPingInterval != activePingIntervalSeconds
                activePingIntervalSeconds = nextPingInterval
                showNotificationSpeed = commandIntent.getBooleanExtra(
                    EXTRA_SHOW_NOTIFICATION_SPEED,
                    showNotificationSpeed,
                )
                val nextShowNotificationPing = commandIntent.getBooleanExtra(
                    EXTRA_SHOW_NOTIFICATION_PING,
                    showNotificationPing,
                )
                val notificationPingChanged = nextShowNotificationPing != showNotificationPing
                showNotificationPing = nextShowNotificationPing
                activeStartIntent?.apply {
                    putExtra(EXTRA_STATS_INTERVAL_SECONDS, activeStatsIntervalSeconds)
                    putExtra(EXTRA_PING_INTERVAL_SECONDS, activePingIntervalSeconds)
                    putExtra(EXTRA_SHOW_NOTIFICATION_SPEED, showNotificationSpeed)
                    putExtra(EXTRA_SHOW_NOTIFICATION_PING, showNotificationPing)
                }
                OrexRayStartIntentStore.updateRuntimeSettings(
                    this,
                    activeStatsIntervalSeconds,
                    activePingIntervalSeconds,
                    showNotificationSpeed,
                    showNotificationPing,
                )
                updateStatsLoopState(restart = intervalChanged)
                updatePingLoopState(
                    restart = pingIntervalChanged ||
                        (notificationPingChanged && showNotificationPing),
                )
                // A settings change is an explicit notification event. It is
                // intentionally the only update when speed rendering is off.
                updateRunningNotification(force = true)
                return restartMode()
            }

            ACTION_UPDATE_METADATA -> {
                val nextTargetId = commandIntent.getStringExtra(EXTRA_TARGET_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: activeTargetId
                val nextTargetName = commandIntent.getStringExtra(EXTRA_TARGET_NAME)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: activeTargetName
                val nextLatencyMs = commandIntent.getIntExtra(EXTRA_LATENCY_MS, -1)
                    .takeIf { it >= 0 }
                val nextPingStatus = normalizePingStatus(
                    commandIntent.getStringExtra(EXTRA_PING_STATUS),
                    nextLatencyMs,
                )
                val nextLatencyProbeUrl = normalizeLatencyProbeUrl(
                    commandIntent.getStringExtra(EXTRA_LATENCY_PROBE_URL),
                )
                val probeChanged = nextLatencyProbeUrl != activeLatencyProbeUrl
                if (nextTargetId == activeTargetId &&
                    nextTargetName == activeTargetName &&
                    nextLatencyMs == activeLatencyMs &&
                    nextPingStatus == activePingStatus &&
                    !probeChanged
                ) {
                    return restartMode()
                }

                activeTargetId = nextTargetId
                activeTargetName = nextTargetName
                activeLatencyMs = nextLatencyMs
                activePingStatus = nextPingStatus
                activeLatencyProbeUrl = nextLatencyProbeUrl
                activeStartIntent?.apply {
                    putExtra(EXTRA_TARGET_ID, activeTargetId)
                    putExtra(EXTRA_TARGET_NAME, activeTargetName)
                    putExtra(EXTRA_LATENCY_MS, activeLatencyMs ?: -1)
                    putExtra(EXTRA_PING_STATUS, activePingStatus)
                    putExtra(EXTRA_LATENCY_PROBE_URL, activeLatencyProbeUrl)
                }
                if (restartServiceOnKill) updateRestartMetadata()
                if (activeMode == MODE_VPN) {
                    updateQuickTileMetadata()
                    OrexRayQuickSettingsTileService.requestRefresh(this)
                }
                if (coreController?.isRunning == true) {
                    updatePingLoopState(restart = probeChanged)
                    updateRunningNotification(force = true)
                    if (statsUiActive) emitConnected()
                }
                return restartMode()
            }

            ACTION_START -> {
                watchdogRestarts.clear()
                OrexRayDiagnosticsStore.automaticRestarts = 0
                OrexRayDiagnosticsStore.lastError = null
                val config = commandIntent.getStringExtra(EXTRA_CONFIG)
                val mode = commandIntent.getStringExtra(EXTRA_MODE) ?: MODE_VPN
                // A stale Activity must not replace metadata for a live core.
                // Dart waits for runtime hydration too, but keep the service
                // safe against any duplicate ACTION_START intent.
                if (coreController?.isRunning == true) {
                    emitConnected()
                    return restartMode()
                }
                activeTargetId = commandIntent.getStringExtra(EXTRA_TARGET_ID)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                activeTargetName = commandIntent.getStringExtra(EXTRA_TARGET_NAME)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: "OrexRay"
                activeLatencyMs = commandIntent.getIntExtra(EXTRA_LATENCY_MS, -1)
                    .takeIf { it >= 0 }
                activePingStatus = normalizePingStatus(
                    commandIntent.getStringExtra(EXTRA_PING_STATUS),
                    activeLatencyMs,
                )
                activeLatencyProbeUrl = normalizeLatencyProbeUrl(
                    commandIntent.getStringExtra(EXTRA_LATENCY_PROBE_URL),
                )
                activeStatsOutboundTags = commandIntent.getStringArrayListExtra(EXTRA_STATS_OUTBOUND_TAGS)
                    ?.map { it.trim() }
                    ?.filter { it == "proxy" || it == "fallback-proxy" || it.matches(Regex("proxy-\\d+")) }
                    ?.distinct()
                    .orEmpty()
                    .ifEmpty { listOf("proxy") }
                activeMtu = commandIntent.getIntExtra(EXTRA_MTU, 1500).coerceIn(1280, 9000)
                activeDnsServers = commandIntent.getStringArrayListExtra(EXTRA_DNS_SERVERS)
                    ?.filter { it.isNotBlank() }
                    ?.take(4)
                    .orEmpty()
                activeSocksPort = commandIntent.getIntExtra(EXTRA_SOCKS_PORT, 20808)
                    .coerceIn(1, 65535)
                activeHttpPort = commandIntent.getIntExtra(EXTRA_HTTP_PORT, 20809)
                    .coerceIn(1, 65535)
                activeLocalProxyInVpn =
                    commandIntent.getBooleanExtra(EXTRA_LOCAL_PROXY_IN_VPN, true)
                activeStatsIntervalSeconds = commandIntent
                    .getIntExtra(EXTRA_STATS_INTERVAL_SECONDS, 2)
                    .let { if (it in setOf(1, 2, 5, 10)) it else 2 }
                activePingIntervalSeconds = commandIntent
                    .getIntExtra(EXTRA_PING_INTERVAL_SECONDS, 60)
                    .let { if (it in setOf(15, 30, 60, 120, 300)) it else 60 }
                showNotificationSpeed =
                    commandIntent.getBooleanExtra(EXTRA_SHOW_NOTIFICATION_SPEED, true)
                showNotificationPing =
                    commandIntent.getBooleanExtra(EXTRA_SHOW_NOTIFICATION_PING, true)
                statsUiActive =
                    commandIntent.getBooleanExtra(EXTRA_STATS_UI_ACTIVE, false)
                restartServiceOnKill = commandIntent.getBooleanExtra(EXTRA_RESTART_SERVICE, true)
                activeAppRoutingMode = commandIntent.getStringExtra(EXTRA_APP_ROUTING_MODE)
                    ?.takeIf {
                        it == APP_ROUTING_ALL ||
                            it == APP_ROUTING_EXCLUDE ||
                            it == APP_ROUTING_ONLY
                    }
                    ?: APP_ROUTING_ALL
                activeAppPackages = commandIntent.getStringArrayListExtra(EXTRA_APP_PACKAGES)
                    ?.map { it.trim() }
                    // The VPN service and Xray core share this package UID.
                    // Letting it into an only-selected VPN can capture its own
                    // outbound sockets and create a recursive route.
                    ?.filter { it.isNotEmpty() && it != packageName }
                    ?.distinct()
                    .orEmpty()

                if (config.isNullOrBlank()) {
                    emitError("Не передан Xray-конфиг", mode)
                    stopSelf()
                    return Service.START_NOT_STICKY
                }
                if (mode != MODE_VPN && mode != MODE_LOCAL_PROXY) {
                    emitError("Неизвестный режим подключения: $mode", mode)
                    stopSelf()
                    return Service.START_NOT_STICKY
                }
                if (mode == MODE_VPN &&
                    activeAppRoutingMode == APP_ROUTING_ONLY &&
                    activeAppPackages.isEmpty()
                ) {
                    emitError("В режиме «Только выбранные» выбери хотя бы одно приложение", mode)
                    stopSelf()
                    return Service.START_NOT_STICKY
                }

                if (restartServiceOnKill) {
                    persistRestartIntent(commandIntent)
                } else {
                    clearRestartState()
                }

                activeStartIntent = Intent(commandIntent)
                activeMode = mode
                lastQuickSettingsStatus = null
                lastNotificationFingerprint = null
                lastNotificationUpdateElapsedMs = 0L
                startInForeground(
                    if (mode == MODE_VPN) {
                        "Подготавливаем защищённый VPN…"
                    } else {
                        "Подготавливаем локальный прокси…"
                    },
                )
                worker.execute { startTunnel(config, mode) }
            }
        }

        return restartMode()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onRevoke() {
        debugInfo("VPN permission revoked")
        restartServiceOnKill = false
        clearRestartState()
        worker.execute { stopTunnel() }
        super.onRevoke()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        debugInfo("UI task removed; core service keeps running")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        statsTask?.cancel(true)
        watchdogTask?.cancel(true)
        pingTask?.cancel(true)
        val controller = coreController
        if (!stopping && controller != null) {
            runCatching { if (controller.isRunning) controller.stopLoop() }
        }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        worker.shutdownNow()
        pingWorker.shutdownNow()
        if (activeService === this) activeService = null
        debugInfo("Core service destroyed")
        super.onDestroy()
    }

    private fun handleStateQuery(intent: Intent, startId: Int): Int {
        val receiver = intent.resultReceiver()
        if (coreController?.isRunning == true || activeStartIntent != null) {
            receiver?.send(0, OrexRayTunnelEvents.toBundle(currentRuntimeState()))
            return restartMode()
        }

        val restored = restoreRestartIntent()
        if (restored != null) {
            val targetId = restored.getStringExtra(EXTRA_TARGET_ID)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            val mode = restored.getStringExtra(EXTRA_MODE) ?: MODE_VPN
            receiver?.send(
                0,
                OrexRayTunnelEvents.toBundle(
                    OrexRayTunnelEvents.event(
                        status = "connecting",
                        mode = mode,
                        targetId = targetId,
                        message = "Восстанавливаем VPN после перезапуска процесса…",
                    ),
                ),
            )
            startService(restored)
            return Service.START_STICKY
        }

        receiver?.send(
            0,
            OrexRayTunnelEvents.toBundle(
                OrexRayTunnelEvents.event(status = "disconnected"),
            ),
        )
        stopSelf(startId)
        return Service.START_NOT_STICKY
    }

    private fun handleDiagnosticsQuery(intent: Intent, startId: Int): Int {
        intent.resultReceiver()?.send(0, diagnosticsBundle())
        if (coreController?.isRunning == true || activeStartIntent != null) {
            return restartMode()
        }
        stopSelf(startId)
        return Service.START_NOT_STICKY
    }

    private fun diagnosticsBundle(): Bundle {
        val snapshot = OrexRayDiagnosticsStore.snapshot()
        return Bundle().apply {
            (snapshot["pid"] as? Number)?.toInt()?.let { putInt("pid", it) }
            putBoolean("coreRunning", snapshot["coreRunning"] == true)
            (snapshot["lastError"] as? String)?.let { putString("lastError", it) }
            (snapshot["lastExitCode"] as? Number)?.toLong()?.let { putLong("lastExitCode", it) }
            putInt(
                "automaticRestarts",
                (snapshot["automaticRestarts"] as? Number)?.toInt() ?: 0,
            )
            putStringArrayList(
                "logs",
                ArrayList((snapshot["logs"] as? List<*>)?.filterIsInstance<String>().orEmpty()),
            )
        }
    }

    private fun restartFromPersistedState(update: (Intent) -> Unit = {}): Boolean {
        val restored = restoreRestartIntent() ?: return false
        update(restored)
        startService(restored)
        return true
    }

    private fun Intent.resultReceiver(): ResultReceiver? = if (Build.VERSION.SDK_INT >= 33) {
        getParcelableExtra(EXTRA_RESULT_RECEIVER, ResultReceiver::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(EXTRA_RESULT_RECEIVER)
    }

    private fun ensureCoreController(): CoreController {
        coreController?.let { return it }

        debugInfo("Initializing Xray core")
        Seq.setContext(applicationContext)
        val envDir = File(filesDir, "xray").apply { mkdirs() }
        Libv2ray.initCoreEnv(envDir.absolutePath, xudpBaseKey())
        return Libv2ray.newCoreController(this).also {
            coreController = it
            debugInfo("Xray core initialized")
        }
    }

    private fun currentRuntimeState(): Map<String, Any?> {
        if (!stopping && coreController?.isRunning == true) {
            return OrexRayTunnelEvents.event(
                status = "connected",
                mode = activeMode,
                targetId = activeTargetId,
                message = if (activeMode == MODE_VPN) {
                    "OrexRay VPN работает"
                } else {
                    "Локальный прокси работает"
                },
                downloadBytes = downloadBytes,
                uploadBytes = uploadBytes,
                downloadBytesPerSecond = downloadBytesPerSecond,
                uploadBytesPerSecond = uploadBytesPerSecond,
                durationSeconds = elapsedSeconds(),
                latencyMs = activeLatencyMs,
                pingStatus = activePingStatus,
            )
        }
        if (!stopping && activeStartIntent != null) {
            return OrexRayTunnelEvents.event(
                status = "connecting",
                mode = activeMode,
                targetId = activeTargetId,
            )
        }
        return OrexRayTunnelEvents.lastEvent
    }

    private fun xudpBaseKey(): String {
        val key = "xudp_base_key_v1"
        secureStore.read(key)?.let { return it }
        // Preserve the pre-multiprocess token once, then keep future writes
        // away from Flutter's secure SharedPreferences file.
        runCatching { AndroidSecureStore(applicationContext).read(key) }
            .getOrNull()
            ?.let { legacy ->
                runCatching { secureStore.write(key, legacy) }
                return legacy
            }
        return secureStore.getOrCreateRandomUrlSafeToken(key, 32)
    }

    private fun startTunnel(config: String, mode: String) {
        val controller = try {
            ensureCoreController()
        } catch (error: Throwable) {
            Log.e(TAG, "Xray core initialization failed", error)
            restartServiceOnKill = false
            clearRestartState()
            emitError("Не удалось инициализировать Xray: ${safeMessage(error)}", mode)
            stopForegroundCompat()
            stopSelf()
            return
        }

        if (controller.isRunning) {
            activeMode = mode
            emitConnected()
            return
        }

        try {
            stopping = false
            activeMode = mode
            downloadBytes = 0
            uploadBytes = 0
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            startedAtElapsedMs = 0
            lastStatsSampleElapsedMs = SystemClock.elapsedRealtime()

            val tunFd = if (mode == MODE_VPN) {
                emitConnecting("Создаём Android VPN…", mode)
                vpnInterface = buildVpnInterface()
                    ?: error("Android не смог создать VPN-интерфейс")
                vpnInterface!!.fd
            } else {
                emitConnecting("Запускаем локальный SOCKS/HTTP прокси…", mode)
                0
            }

            emitConnecting("Запускаем Xray Core…", mode)
            debugInfo("Starting Xray mode=$mode tunFd=$tunFd")
            controller.startLoop(config, tunFd)
            if (!controller.isRunning) {
                error("Xray Core завершился сразу после запуска")
            }

            startedAtElapsedMs = SystemClock.elapsedRealtime()
            if (mode == MODE_VPN) {
                activeStartIntent?.let { intent ->
                    runCatching { OrexRayStartIntentStore.saveQuickTileVpn(this, intent) }
                        .onFailure { Log.w(TAG, "Could not save Quick Settings VPN state", it) }
                }
            }
            OrexRayDiagnosticsStore.coreRunning = true
            emitConnected()
            updateStatsLoopState()
            startWatchdog()
            updatePingLoopState()
            updateRunningNotification(force = true)
            debugInfo("Xray started successfully mode=$mode")
        } catch (error: Throwable) {
            OrexRayDiagnosticsStore.coreRunning = false
            OrexRayDiagnosticsStore.lastError = safeMessage(error)
            OrexRayDiagnosticsStore.log("Start failed: ${safeMessage(error)}")
            Log.e(TAG, "Could not start Xray mode=$mode", error)
            cleanupAfterFailure()
            restartServiceOnKill = false
            clearRestartState()
            emitError(safeMessage(error), mode)
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun startWatchdog() {
        watchdogTask?.cancel(false)
        watchdogTask = worker.scheduleAtFixedRate(
            {
                if (stopping) return@scheduleAtFixedRate
                val controller = coreController ?: return@scheduleAtFixedRate
                if (controller.isRunning || activeStartIntent == null) return@scheduleAtFixedRate

                val now = SystemClock.elapsedRealtime()
                while (watchdogRestarts.isNotEmpty() &&
                    now - watchdogRestarts.first() > 60_000L
                ) {
                    watchdogRestarts.removeFirst()
                }
                if (watchdogRestarts.size >= 3) {
                    watchdogTask?.cancel(false)
                    OrexRayDiagnosticsStore.lastError =
                        "Android watchdog stopped after 3 restarts in one minute"
                    emitError(
                        "Xray несколько раз подряд завершился. Watchdog остановлен, чтобы избежать бесконечного цикла.",
                    )
                    return@scheduleAtFixedRate
                }

                watchdogRestarts.addLast(now)
                OrexRayDiagnosticsStore.automaticRestarts++
                OrexRayDiagnosticsStore.log(
                    "Watchdog restart ${watchdogRestarts.size}/3 after unexpected core stop",
                )
                restartCoreFromWatchdog()
            },
            5,
            5,
            TimeUnit.SECONDS,
        )
    }

    private fun restartCoreFromWatchdog() {
        val intent = activeStartIntent ?: return
        val config = intent.getStringExtra(EXTRA_CONFIG)?.takeIf { it.isNotBlank() } ?: return
        val mode = intent.getStringExtra(EXTRA_MODE) ?: activeMode
        watchdogTask?.cancel(false)
        watchdogTask = null
        statsTask?.cancel(false)
        statsTask = null
        pingTask?.cancel(false)
        pingTask = null
        OrexRayDiagnosticsStore.coreRunning = false
        runCatching { if (coreController?.isRunning == true) coreController?.stopLoop() }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        Thread.sleep(600)
        startTunnel(config, mode)
    }

    private fun restartMode(): Int = if (restartServiceOnKill) {
        Service.START_STICKY
    } else {
        Service.START_NOT_STICKY
    }

    private fun persistRestartIntent(intent: Intent) {
        OrexRayStartIntentStore.saveRestart(this, intent)
    }

    private fun restoreRestartIntent(): Intent? =
        OrexRayStartIntentStore.loadRestart(this)

    private fun updateRestartMetadata() {
        OrexRayStartIntentStore.updateRestartMetadata(
            this,
            activeTargetId,
            activeTargetName,
            activeLatencyMs,
            activePingStatus,
            activeLatencyProbeUrl,
        )
    }

    private fun updateQuickTileMetadata() {
        OrexRayStartIntentStore.updateQuickTileMetadata(
            this,
            activeTargetId,
            activeTargetName,
            activeLatencyMs,
            activePingStatus,
            activeLatencyProbeUrl,
        )
    }

    private fun clearRestartState() {
        OrexRayStartIntentStore.clearRestart(this)
    }

    private fun buildVpnInterface(): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession("OrexRay")
            .setMtu(activeMtu)
            .addAddress("10.77.0.1", 24)
            .addAddress("fd77:6f72:6578::1", 64)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)

        activeDnsServers.forEach { builder.addDnsServer(it) }

        when (activeAppRoutingMode) {
            APP_ROUTING_ONLY -> {
                val addedPackages = activeAppPackages.count { addAllowedPackage(builder, it) }
                if (addedPackages == 0) {
                    error("Ни одно выбранное приложение больше не установлено")
                }
            }

            APP_ROUTING_EXCLUDE -> {
                addDisallowedPackage(builder, packageName)
                activeAppPackages.forEach { addDisallowedPackage(builder, it) }
            }

            else -> addDisallowedPackage(builder, packageName)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return builder.establish()
    }

    private fun addAllowedPackage(builder: Builder, packageName: String): Boolean {
        return try {
            builder.addAllowedApplication(packageName)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            Log.w(TAG, "Allowed package disappeared: $packageName")
            false
        }
    }

    private fun addDisallowedPackage(builder: Builder, packageName: String) {
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            Log.w(TAG, "Disallowed package disappeared: $packageName")
        }
    }

    @Synchronized
    private fun updateStatsLoopState(restart: Boolean = false) {
        if (!shouldPollStats()) {
            if (statsTask != null) {
                debugInfo("Stats loop stopped: no active UI or notification consumer")
                statsTask?.cancel(false)
                statsTask = null
            }
            return
        }

        if (statsTask != null && !restart) return
        statsTask?.cancel(false)
        val interval = statsPollIntervalSeconds().toLong()
        debugInfo(
            "Stats loop started: interval=${interval}s, ui=$statsUiActive, " +
                "notificationSpeed=$showNotificationSpeed",
        )
        statsTask = worker.scheduleAtFixedRate(
            {
                val controller = coreController ?: return@scheduleAtFixedRate
                if (!controller.isRunning || stopping) {
                    return@scheduleAtFixedRate
                }
                val notificationSpeedVisible = isNotificationSpeedVisible()
                if (!statsUiActive && !notificationSpeedVisible) {
                    // The notification can be disabled in Android settings
                    // while the UI is in the background. Stop the recurring
                    // job on its next scheduled tick instead of keeping an
                    // otherwise idle wake-up alive.
                    updateStatsLoopState()
                    return@scheduleAtFixedRate
                }
                val delta = queryTrafficDelta(controller)
                val now = SystemClock.elapsedRealtime()
                val elapsedMs = if (lastStatsSampleElapsedMs > 0L) {
                    (now - lastStatsSampleElapsedMs).coerceAtLeast(1L)
                } else {
                    interval * 1_000L
                }
                lastStatsSampleElapsedMs = now
                downloadBytes += delta.download
                uploadBytes += delta.upload
                downloadBytesPerSecond = delta.download * 1_000L / elapsedMs
                uploadBytesPerSecond = delta.upload * 1_000L / elapsedMs
                if (statsUiActive) emitConnected()
                if (notificationSpeedVisible) updateRunningNotification()
            },
            interval,
            interval,
            TimeUnit.SECONDS,
        )
    }

    private fun shouldPollStats(): Boolean =
        !stopping && coreController?.isRunning == true &&
            (statsUiActive || isNotificationSpeedVisible())

    private fun statsPollIntervalSeconds(): Int =
        if (statsUiActive) activeStatsIntervalSeconds else max(5, activeStatsIntervalSeconds)

    private fun isNotificationChannelVisible(): Boolean {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            !manager.areNotificationsEnabled()
        ) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
            return channel != null &&
                channel.importance != NotificationManager.IMPORTANCE_NONE
        }
        return true
    }

    private fun isNotificationSpeedVisible(): Boolean =
        showNotificationSpeed && isNotificationChannelVisible()

    private fun isNotificationPingVisible(): Boolean =
        showNotificationPing && isNotificationChannelVisible()

    private fun queryTrafficDelta(controller: CoreController): TrafficDelta {
        var download = 0L
        var upload = 0L
        activeStatsOutboundTags.forEach { tag ->
            download += runCatching {
                controller.queryStats(tag, "downlink").coerceAtLeast(0)
            }.getOrDefault(0L)
            upload += runCatching {
                controller.queryStats(tag, "uplink").coerceAtLeast(0)
            }.getOrDefault(0L)
        }
        return TrafficDelta(download, upload)
    }

    private fun emitTunnelEvent(value: Map<String, Any?>) {
        OrexRayTunnelEvents.emit(this, value)
        val status = value["status"] as? String
        if (status != null && status != lastQuickSettingsStatus) {
            lastQuickSettingsStatus = status
            OrexRayQuickSettingsTileService.requestRefresh(this)
        }
    }

    private fun emitConnecting(message: String, mode: String = activeMode) {
        emitTunnelEvent(
            OrexRayTunnelEvents.event(
                status = "connecting",
                mode = mode,
                targetId = activeTargetId,
                message = message,
            ),
        )
    }

    private fun emitConnected() {
        emitTunnelEvent(
            OrexRayTunnelEvents.event(
                status = "connected",
                mode = activeMode,
                targetId = activeTargetId,
                message = if (activeMode == MODE_VPN) {
                    "OrexRay VPN работает"
                } else {
                    "Локальный прокси работает"
                },
                downloadBytes = downloadBytes,
                uploadBytes = uploadBytes,
                downloadBytesPerSecond = downloadBytesPerSecond,
                uploadBytesPerSecond = uploadBytesPerSecond,
                durationSeconds = elapsedSeconds(),
                latencyMs = activeLatencyMs,
                pingStatus = activePingStatus,
            ),
        )
    }

    private fun stopTunnel() {
        if (stopping) return
        stopping = true
        activeStartIntent = null
        clearRestartState()

        emitTunnelEvent(
            OrexRayTunnelEvents.event(
                status = "disconnecting",
                mode = activeMode,
                targetId = activeTargetId,
                message = if (activeMode == MODE_VPN) {
                    "Останавливаем VPN…"
                } else {
                    "Останавливаем локальный прокси…"
                },
                downloadBytes = downloadBytes,
                uploadBytes = uploadBytes,
                downloadBytesPerSecond = downloadBytesPerSecond,
                uploadBytesPerSecond = uploadBytesPerSecond,
                durationSeconds = elapsedSeconds(),
            ),
        )

        statsTask?.cancel(false)
        statsTask = null
        watchdogTask?.cancel(false)
        watchdogTask = null
        pingTask?.cancel(false)
        pingTask = null
        OrexRayDiagnosticsStore.coreRunning = false
        val controller = coreController
        runCatching { if (controller?.isRunning == true) controller.stopLoop() }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        stopForegroundCompat()

        emitTunnelEvent(
            OrexRayTunnelEvents.event(
                status = "disconnected",
                mode = activeMode,
                targetId = activeTargetId,
            ),
        )
        debugInfo("Xray stopped mode=$activeMode")
        stopSelf()
    }

    private fun cleanupAfterFailure() {
        activeStartIntent = null
        statsTask?.cancel(false)
        statsTask = null
        watchdogTask?.cancel(false)
        watchdogTask = null
        pingTask?.cancel(false)
        pingTask = null
        OrexRayDiagnosticsStore.coreRunning = false
        val controller = coreController
        runCatching { if (controller?.isRunning == true) controller.stopLoop() }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
    }

    private fun elapsedSeconds(): Long = if (startedAtElapsedMs == 0L) {
        0L
    } else {
        (SystemClock.elapsedRealtime() - startedAtElapsedMs) / 1000L
    }

    private fun emitError(message: String, mode: String = activeMode) {
        emitTunnelEvent(
            OrexRayTunnelEvents.event(
                status = "error",
                mode = mode,
                targetId = activeTargetId,
                errorMessage = message,
                downloadBytes = downloadBytes,
                uploadBytes = uploadBytes,
                downloadBytesPerSecond = downloadBytesPerSecond,
                uploadBytesPerSecond = uploadBytesPerSecond,
                durationSeconds = elapsedSeconds(),
            ),
        )
    }

    @Synchronized
    private fun updatePingLoopState(restart: Boolean = false) {
        val controllerRunning = coreController?.isRunning == true && !stopping
        val wantsRouteHealth = statsUiActive || isNotificationPingVisible()
        val canProbeRoute = activeMode != MODE_VPN || activeLocalProxyInVpn
        if (!wantsRouteHealth || !controllerRunning || !canProbeRoute) {
            pingTask?.cancel(false)
            pingTask = null
            if (!wantsRouteHealth && controllerRunning) {
                // No foreground/UI consumer exists. Clear stale health so a
                // later UI attach does not flash an old green result before
                // the first fresh probe completes.
                activeLatencyMs = null
                activePingStatus = "unknown"
            }
            if (wantsRouteHealth && controllerRunning && !canProbeRoute &&
                activePingStatus != "unavailable"
            ) {
                activeLatencyMs = null
                activePingStatus = "unavailable"
                if (isNotificationPingVisible()) updateRunningNotification(force = true)
                if (statsUiActive) emitConnected()
            }
            return
        }

        if (pingTask != null && !restart) return
        pingTask?.cancel(false)
        pingTask = pingWorker.scheduleAtFixedRate(
            {
                if (!shouldMeasureRouteLatency()) {
                    updatePingLoopState()
                    return@scheduleAtFixedRate
                }
                measureAndPublishRouteLatency()
            },
            PING_INITIAL_DELAY_SECONDS,
            activePingIntervalSeconds.toLong(),
            TimeUnit.SECONDS,
        )
    }

    private fun shouldMeasureRouteLatency(): Boolean =
        !stopping &&
            coreController?.isRunning == true &&
            (statsUiActive || isNotificationPingVisible())

    private fun measureAndPublishRouteLatency() {
        if (!shouldMeasureRouteLatency()) return
        val measurement = measureRouteLatency()
        if (!shouldMeasureRouteLatency()) return
        activeLatencyMs = measurement.latencyMs
        activePingStatus = measurement.status
        if (isNotificationPingVisible()) updateRunningNotification(force = true)
        if (statsUiActive) emitConnected()
    }

    private fun measureRouteLatency(): PingMeasurement {
        val proxy = Proxy(
            Proxy.Type.HTTP,
            InetSocketAddress("127.0.0.1", activeHttpPort),
        )
        val connection = runCatching {
            URL(activeLatencyProbeUrl).openConnection(proxy) as HttpURLConnection
        }.getOrElse {
            return PingMeasurement(null, "unavailable")
        }
        connection.connectTimeout = PING_TIMEOUT_MS
        connection.readTimeout = PING_TIMEOUT_MS
        connection.instanceFollowRedirects = false
        connection.requestMethod = "GET"
        connection.setRequestProperty("Connection", "close")
        val startedAt = SystemClock.elapsedRealtime()
        return try {
            val responseCode = connection.responseCode
            // Match the Dart route probe: the configured endpoint is healthy
            // only when it returns a 2xx response. Redirects are deliberately
            // not followed so a public probe cannot bounce into a local URL.
            if (responseCode in 200..299) {
                val elapsed = (SystemClock.elapsedRealtime() - startedAt)
                    .coerceAtLeast(1L)
                    .coerceAtMost(Int.MAX_VALUE.toLong())
                    .toInt()
                PingMeasurement(elapsed, "success")
            } else {
                PingMeasurement(null, "unavailable")
            }
        } catch (_: SocketTimeoutException) {
            PingMeasurement(null, "timeout")
        } catch (error: Throwable) {
            debugInfo("Notification ping failed: ${safeMessage(error)}")
            PingMeasurement(null, "unavailable")
        } finally {
            connection.disconnect()
        }
    }

    private fun normalizeLatencyProbeUrl(value: String?): String {
        val normalized = value?.trim().orEmpty()
        return if (normalized.startsWith("https://") || normalized.startsWith("http://")) {
            normalized
        } else {
            DEFAULT_LATENCY_PROBE_URL
        }
    }

    private fun normalizePingStatus(value: String?, latencyMs: Int?): String =
        when (value?.trim()?.lowercase()) {
            "success" -> if (latencyMs != null) "success" else "unknown"
            "timeout" -> "timeout"
            "unavailable" -> "unavailable"
            else -> if (latencyMs != null) "success" else "unknown"
        }

    private fun safeMessage(error: Throwable): String {
        return error.message?.takeIf { it.isNotBlank() } ?: error.javaClass.simpleName
    }

    private fun startInForeground(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateRunningNotification(force: Boolean = false) {
        val parts = mutableListOf<String>()
        if (showNotificationSpeed) {
            parts += "↓ ${formatSpeed(downloadBytesPerSecond)}"
            parts += "↑ ${formatSpeed(uploadBytesPerSecond)}"
        }
        if (showNotificationPing) {
            parts += when (activePingStatus) {
                "success" -> activeLatencyMs?.let { "$it мс" } ?: "—"
                else -> "—"
            }
        }
        if (parts.isEmpty()) {
            parts += if (activeMode == MODE_VPN) {
                "VPN защищает трафик"
            } else {
                "SOCKS :$activeSocksPort · HTTP :$activeHttpPort"
            }
        }
        updateNotification(parts.joinToString(" · "), force)
    }

    private fun updateNotification(text: String, force: Boolean) {
        val fingerprint = listOf(
            activeTargetName,
            activeMode,
            activeLocalProxyInVpn.toString(),
            activeSocksPort.toString(),
            activeHttpPort.toString(),
            text,
        ).joinToString("|")
        if (fingerprint == lastNotificationFingerprint) return

        val now = SystemClock.elapsedRealtime()
        if (!force &&
            lastNotificationUpdateElapsedMs > 0L &&
            now - lastNotificationUpdateElapsedMs < NOTIFICATION_MIN_UPDATE_MS
        ) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
        lastNotificationFingerprint = fingerprint
        lastNotificationUpdateElapsedMs = now
    }

    private fun buildNotification(text: String): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = Intent(this, OrexRayVpnService::class.java)
            .setAction(ACTION_STOP)
        val stopPendingIntent = PendingIntent.getService(
            this,
            STOP_REQUEST_CODE,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.orexray_icon)
            .setLargeIcon(notificationLargeIcon)
            .setContentTitle("OrexRay · $activeTargetName")
            .setContentText(text)
            .setSubText(
                if (activeMode == MODE_VPN) {
                    if (activeLocalProxyInVpn) {
                        "VPN · SOCKS :$activeSocksPort · HTTP :$activeHttpPort"
                    } else {
                        "VPN"
                    }
                } else {
                    "Локальный прокси"
                },
            )
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(0, "Отключить", stopPendingIntent)
            .build()
    }

    private fun formatSpeed(bytesPerSecond: Long): String {
        val value = bytesPerSecond.coerceAtLeast(0)
        return when {
            value >= 1024L * 1024L -> String.format("%.1f MB/s", value / (1024.0 * 1024.0))
            value >= 1024L -> String.format("%.0f KB/s", value / 1024.0)
            else -> "$value B/s"
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "OrexRay",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Состояние VPN, скорость и локальный прокси OrexRay"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun debugInfo(message: String) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) Log.i(TAG, message)
    }

    private fun debugLog(message: String) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) Log.d(TAG, message)
    }

    override fun startup(): Long = 0L

    override fun shutdown(): Long = 0L

    override fun onEmitStatus(code: Long, message: String?): Long {
        if (!message.isNullOrBlank()) {
            OrexRayDiagnosticsStore.log("core[$code] $message")
            debugLog("Core status code=$code message=$message")
        }
        return 0L
    }
}
