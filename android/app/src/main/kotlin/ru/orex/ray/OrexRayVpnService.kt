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
import android.util.Log
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class OrexRayVpnService : VpnService(), CoreCallbackHandler {
    companion object {
        const val ACTION_START = "ru.orex.ray.action.START"
        const val ACTION_STOP = "ru.orex.ray.action.STOP"
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_MODE = "connection_mode"

        const val MODE_VPN = "vpn_tun"
        const val MODE_LOCAL_PROXY = "local_proxy"

        private const val TAG = "OrexRay"
        private const val NOTIFICATION_CHANNEL_ID = "orexray_vpn"
        private const val NOTIFICATION_ID = 7701
    }

    private val worker = Executors.newSingleThreadScheduledExecutor()
    private var coreController: CoreController? = null
    private var vpnInterface: ParcelFileDescriptor? = null
    private var statsTask: ScheduledFuture<*>? = null
    private var startedAtElapsedMs = 0L
    private var downloadBytes = 0L
    private var uploadBytes = 0L
    private var activeMode = MODE_VPN

    @Volatile
    private var stopping = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.i(TAG, "Core service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> worker.execute { stopTunnel() }
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_VPN
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

                // Android requires a foreground-service notification very soon after
                // startForegroundService(). Native core initialization can be slow on
                // some devices, so the notification is shown before any heavy work.
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
        return Service.START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked")
        worker.execute { stopTunnel() }
        super.onRevoke()
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
        Libv2ray.initCoreEnv(envDir.absolutePath, "orexray")
        return Libv2ray.newCoreController(this).also {
            coreController = it
            Log.i(TAG, "Xray core initialized")
        }
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
            updateNotification(
                if (mode == MODE_VPN) {
                    "VPN защищает трафик"
                } else {
                    "SOCKS 127.0.0.1:20808 · HTTP 127.0.0.1:20809"
                },
            )
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
            .setMtu(1500)
            .addAddress("10.77.0.1", 24)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")

        // Xray lives in this application. Excluding the app keeps its outbound
        // sockets outside the VPN and prevents the VPN from tunnelling itself.
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            Log.w(TAG, "Could not exclude OrexRay package from VPN")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return builder.establish()
    }

    private fun startStatsLoop() {
        statsTask?.cancel(false)
        statsTask = worker.scheduleAtFixedRate(
            {
                val controller = coreController ?: return@scheduleAtFixedRate
                if (!controller.isRunning || stopping) return@scheduleAtFixedRate
                downloadBytes += controller.queryStats("proxy", "downlink").coerceAtLeast(0)
                uploadBytes += controller.queryStats("proxy", "uplink").coerceAtLeast(0)
                emitConnected()
            },
            1,
            1,
            TimeUnit.SECONDS,
        )
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
        val durationSeconds = if (startedAtElapsedMs == 0L) {
            0L
        } else {
            (SystemClock.elapsedRealtime() - startedAtElapsedMs) / 1000L
        }
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
                durationSeconds = durationSeconds,
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

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun buildNotification(text: String): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
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
            .setContentTitle("OrexRay")
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "OrexRay",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Состояние VPN и локального прокси OrexRay"
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
