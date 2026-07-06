package ru.orex.ray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.Settings
import android.util.Base64
import android.util.Log
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.max

class OrexRayVpnService : VpnService(), CoreCallbackHandler {
    companion object {
        const val ACTION_START = "ru.orex.ray.action.START"
        const val ACTION_STOP = "ru.orex.ray.action.STOP"
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_MODE = "connection_mode"
        const val EXTRA_TARGET_NAME = "target_name"
        const val EXTRA_STATS_OUTBOUND_TAGS = "stats_outbound_tags"
        const val EXTRA_MTU = "vpn_mtu"
        const val EXTRA_DNS_SERVERS = "vpn_dns_servers"
        const val EXTRA_SOCKS_PORT = "socks_port"
        const val EXTRA_HTTP_PORT = "http_port"
        const val EXTRA_STATS_INTERVAL_SECONDS = "stats_interval_seconds"
        const val EXTRA_SHOW_NOTIFICATION_SPEED = "show_notification_speed"
        const val EXTRA_RESTART_SERVICE = "restart_service"
        const val EXTRA_APP_ROUTING_MODE = "app_routing_mode"
        const val EXTRA_APP_PACKAGES = "app_packages"

        const val MODE_VPN = "vpn_tun"
        const val MODE_LOCAL_PROXY = "local_proxy"

        private const val APP_ROUTING_ALL = "all"
        private const val APP_ROUTING_EXCLUDE = "exclude_selected"
        private const val APP_ROUTING_ONLY = "only_selected"

        private const val TAG = "OrexRay"
        private const val NOTIFICATION_CHANNEL_ID = "orexray_vpn"
        private const val NOTIFICATION_ID = 7701
        private const val STOP_REQUEST_CODE = 7702
    }

    private data class TrafficDelta(val download: Long, val upload: Long)

    private val worker = Executors.newSingleThreadScheduledExecutor()
    private var coreController: CoreController? = null
    private var vpnInterface: ParcelFileDescriptor? = null
    private var statsTask: ScheduledFuture<*>? = null
    private var startedAtElapsedMs = 0L
    private var downloadBytes = 0L
    private var uploadBytes = 0L
    private var downloadBytesPerSecond = 0L
    private var uploadBytesPerSecond = 0L
    private var activeMode = MODE_VPN
    private var activeTargetName = "OrexRay"
    private var activeStatsOutboundTags = listOf("proxy")
    private var activeMtu = 1500
    private var activeDnsServers = listOf("1.1.1.1", "8.8.8.8")
    private var activeSocksPort = 20808
    private var activeHttpPort = 20809
    private var activeStatsIntervalSeconds = 2
    private var showNotificationSpeed = true
    private var restartServiceOnKill = true
    private var activeAppRoutingMode = APP_ROUTING_ALL
    private var activeAppPackages = emptyList<String>()

    @Volatile
    private var stopping = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.i(TAG, "Core service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                restartServiceOnKill = false
                worker.execute { stopTunnel() }
                return Service.START_NOT_STICKY
            }

            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_VPN
                activeTargetName = intent.getStringExtra(EXTRA_TARGET_NAME)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: "OrexRay"
                activeStatsOutboundTags = intent.getStringArrayListExtra(EXTRA_STATS_OUTBOUND_TAGS)
                    ?.map { it.trim() }
                    ?.filter { it == "proxy" || it.matches(Regex("proxy-\\d+")) }
                    ?.distinct()
                    .orEmpty()
                    .ifEmpty { listOf("proxy") }
                activeMtu = intent.getIntExtra(EXTRA_MTU, 1500).coerceIn(1280, 9000)
                activeDnsServers = intent.getStringArrayListExtra(EXTRA_DNS_SERVERS)
                    ?.filter { it.isNotBlank() }
                    ?.take(4)
                    .orEmpty()
                    .ifEmpty { listOf("1.1.1.1", "8.8.8.8") }
                activeSocksPort = intent.getIntExtra(EXTRA_SOCKS_PORT, 20808)
                    .coerceIn(1, 65535)
                activeHttpPort = intent.getIntExtra(EXTRA_HTTP_PORT, 20809)
                    .coerceIn(1, 65535)
                activeStatsIntervalSeconds = intent
                    .getIntExtra(EXTRA_STATS_INTERVAL_SECONDS, 2)
                    .let { if (it in setOf(1, 2, 5, 10)) it else 2 }
                showNotificationSpeed =
                    intent.getBooleanExtra(EXTRA_SHOW_NOTIFICATION_SPEED, true)
                restartServiceOnKill = intent.getBooleanExtra(EXTRA_RESTART_SERVICE, true)
                activeAppRoutingMode = intent.getStringExtra(EXTRA_APP_ROUTING_MODE)
                    ?.takeIf {
                        it == APP_ROUTING_ALL ||
                            it == APP_ROUTING_EXCLUDE ||
                            it == APP_ROUTING_ONLY
                    }
                    ?: APP_ROUTING_ALL
                activeAppPackages = intent.getStringArrayListExtra(EXTRA_APP_PACKAGES)
                    ?.filter { it.isNotBlank() }
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

                activeMode = mode
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

        return if (restartServiceOnKill) {
            Service.START_REDELIVER_INTENT
        } else {
            Service.START_NOT_STICKY
        }
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked")
        restartServiceOnKill = false
        worker.execute { stopTunnel() }
        super.onRevoke()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "UI task removed; core service keeps running")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        statsTask?.cancel(true)
        val controller = coreController
        if (!stopping && controller != null) {
            runCatching { if (controller.isRunning) controller.stopLoop() }
        }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        worker.shutdownNow()
        Log.i(TAG, "Core service destroyed")
        super.onDestroy()
    }

    private fun ensureCoreController(): CoreController {
        coreController?.let { return it }

        Log.i(TAG, "Initializing Xray core")
        Seq.setContext(applicationContext)
        val envDir = File(filesDir, "xray").apply { mkdirs() }
        Libv2ray.initCoreEnv(envDir.absolutePath, xudpBaseKey())
        return Libv2ray.newCoreController(this).also {
            coreController = it
            Log.i(TAG, "Xray core initialized")
        }
    }

    private fun xudpBaseKey(): String {
        val androidId = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ANDROID_ID,
        ).orEmpty()
        val raw = androidId.toByteArray(Charsets.UTF_8).copyOf(32)
        return Base64.encodeToString(
            raw,
            Base64.NO_PADDING or Base64.NO_WRAP or Base64.URL_SAFE,
        )
    }

    private fun startTunnel(config: String, mode: String) {
        val controller = try {
            ensureCoreController()
        } catch (error: Throwable) {
            Log.e(TAG, "Xray core initialization failed", error)
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
            Log.i(TAG, "Starting Xray mode=$mode tunFd=$tunFd")
            controller.startLoop(config, tunFd)
            if (!controller.isRunning) {
                error("Xray Core завершился сразу после запуска")
            }

            startedAtElapsedMs = SystemClock.elapsedRealtime()
            emitConnected()
            startStatsLoop()
            updateRunningNotification()
            Log.i(TAG, "Xray started successfully mode=$mode")
        } catch (error: Throwable) {
            Log.e(TAG, "Could not start Xray mode=$mode", error)
            cleanupAfterFailure()
            emitError(safeMessage(error), mode)
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun buildVpnInterface(): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession("OrexRay")
            .setMtu(activeMtu)
            .addAddress("10.77.0.1", 24)
            .addRoute("0.0.0.0", 0)

        activeDnsServers.forEach { builder.addDnsServer(it) }

        when (activeAppRoutingMode) {
            APP_ROUTING_ONLY -> {
                activeAppPackages.forEach { addAllowedPackage(builder, it) }
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

    private fun addAllowedPackage(builder: Builder, packageName: String) {
        try {
            builder.addAllowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            Log.w(TAG, "Allowed package disappeared: $packageName")
        }
    }

    private fun addDisallowedPackage(builder: Builder, packageName: String) {
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            Log.w(TAG, "Disallowed package disappeared: $packageName")
        }
    }

    private fun startStatsLoop() {
        statsTask?.cancel(false)
        val interval = activeStatsIntervalSeconds.toLong()
        statsTask = worker.scheduleAtFixedRate(
            {
                val controller = coreController ?: return@scheduleAtFixedRate
                if (!controller.isRunning || stopping) return@scheduleAtFixedRate
                val delta = queryTrafficDelta(controller)
                downloadBytes += delta.download
                uploadBytes += delta.upload
                downloadBytesPerSecond = delta.download / max(1, activeStatsIntervalSeconds)
                uploadBytesPerSecond = delta.upload / max(1, activeStatsIntervalSeconds)
                emitConnected()
                if (showNotificationSpeed) updateRunningNotification()
            },
            interval,
            interval,
            TimeUnit.SECONDS,
        )
    }

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

    private fun emitConnecting(message: String, mode: String = activeMode) {
        OrexRayTunnelEvents.emit(
            OrexRayTunnelEvents.event(
                status = "connecting",
                mode = mode,
                message = message,
            ),
        )
    }

    private fun emitConnected() {
        OrexRayTunnelEvents.emit(
            OrexRayTunnelEvents.event(
                status = "connected",
                mode = activeMode,
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
            ),
        )
    }

    private fun stopTunnel() {
        if (stopping) return
        stopping = true

        OrexRayTunnelEvents.emit(
            OrexRayTunnelEvents.event(
                status = "disconnecting",
                mode = activeMode,
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
        val controller = coreController
        runCatching { if (controller?.isRunning == true) controller.stopLoop() }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        stopForegroundCompat()

        OrexRayTunnelEvents.emit(
            OrexRayTunnelEvents.event(
                status = "disconnected",
                mode = activeMode,
            ),
        )
        Log.i(TAG, "Xray stopped mode=$activeMode")
        stopSelf()
    }

    private fun cleanupAfterFailure() {
        statsTask?.cancel(false)
        statsTask = null
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
        OrexRayTunnelEvents.emit(
            OrexRayTunnelEvents.event(
                status = "error",
                mode = mode,
                errorMessage = message,
                downloadBytes = downloadBytes,
                uploadBytes = uploadBytes,
                downloadBytesPerSecond = downloadBytesPerSecond,
                uploadBytesPerSecond = uploadBytesPerSecond,
                durationSeconds = elapsedSeconds(),
            ),
        )
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

    private fun updateRunningNotification() {
        val text = if (showNotificationSpeed) {
            "↓ ${formatSpeed(downloadBytesPerSecond)} · ↑ ${formatSpeed(uploadBytesPerSecond)}"
        } else if (activeMode == MODE_VPN) {
            "VPN защищает трафик"
        } else {
            "SOCKS :$activeSocksPort · HTTP :$activeHttpPort"
        }
        updateNotification(text)
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
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
            .setContentTitle("OrexRay · $activeTargetName")
            .setContentText(text)
            .setSubText(if (activeMode == MODE_VPN) "VPN" else "Локальный прокси")
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

    override fun startup(): Long = 0L

    override fun shutdown(): Long = 0L

    override fun onEmitStatus(code: Long, message: String?): Long {
        if (!message.isNullOrBlank()) {
            Log.d(TAG, "Core status code=$code message=$message")
        }
        return 0L
    }
}
