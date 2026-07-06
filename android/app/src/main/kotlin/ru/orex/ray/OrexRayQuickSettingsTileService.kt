package ru.orex.ray

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

class OrexRayQuickSettingsTileService : TileService() {
    companion object {
        private const val TAG = "OrexRay"
        private const val OPEN_APP_REQUEST_CODE = 7731
        private const val PERMISSION_REQUEST_CODE = 7732

        fun requestRefresh(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            runCatching {
                TileService.requestListeningState(
                    context.applicationContext,
                    ComponentName(context, OrexRayQuickSettingsTileService::class.java),
                )
            }.onFailure { Log.w(TAG, "Could not request Quick Settings tile refresh", it) }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileFromRuntime()
    }

    override fun onClick() {
        super.onClick()

        val event = OrexRayRuntimeStateStore.load(this)
        val status = event["status"] as? String ?: "disconnected"
        val mode = event["mode"] as? String ?: OrexRayVpnService.MODE_VPN

        when {
            mode == OrexRayVpnService.MODE_VPN &&
                (status == "connected" || status == "connecting") -> stopVpn()

            status == "disconnecting" -> stopVpn()

            mode != OrexRayVpnService.MODE_VPN &&
                (status == "connected" || status == "connecting") -> render(
                state = Tile.STATE_UNAVAILABLE,
                subtitle = "Сначала отключи локальный прокси",
            )

            else -> startVpn()
        }
    }

    private fun startVpn() {
        val startIntent = OrexRayStartIntentStore.loadQuickTileVpn(this)
        if (startIntent == null) {
            openApp()
            return
        }

        val needsVpnPermission = VpnService.prepare(this) != null
        if (needsVpnPermission) {
            openPermissionFlow()
            return
        }

        render(state = Tile.STATE_ACTIVE, subtitle = "Подключение…")
        runCatching { startCoreService(startIntent) }
            .onFailure {
                Log.e(TAG, "Could not start VPN from Quick Settings", it)
                openPermissionFlow()
            }
    }

    private fun stopVpn() {
        render(state = Tile.STATE_INACTIVE, subtitle = "Отключение…")
        val stopIntent = Intent(this, OrexRayVpnService::class.java)
            .setAction(OrexRayVpnService.ACTION_STOP)
        runCatching { startService(stopIntent) }
            .onFailure {
                Log.e(TAG, "Could not stop VPN from Quick Settings", it)
                OrexRayRuntimeStateStore.save(
                    this,
                    OrexRayTunnelEvents.event(
                        status = "disconnected",
                        mode = OrexRayVpnService.MODE_VPN,
                    ),
                )
                updateTileFromRuntime()
            }
    }

    private fun startCoreService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun openPermissionFlow() {
        launchActivityAndCollapse(
            Intent(this, OrexRayVpnPermissionActivity::class.java),
            PERMISSION_REQUEST_CODE,
        )
    }

    private fun openApp() {
        launchActivityAndCollapse(
            Intent(this, MainActivity::class.java),
            OPEN_APP_REQUEST_CODE,
        )
    }

    private fun launchActivityAndCollapse(intent: Intent, requestCode: Int) {
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTileFromRuntime() {
        val event = OrexRayRuntimeStateStore.load(this)
        val status = event["status"] as? String ?: "disconnected"
        val mode = event["mode"] as? String ?: OrexRayVpnService.MODE_VPN
        val savedVpn = OrexRayStartIntentStore.loadQuickTileVpn(this)
        val targetName = savedVpn
            ?.getStringExtra(OrexRayVpnService.EXTRA_TARGET_NAME)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        when {
            mode != OrexRayVpnService.MODE_VPN &&
                (status == "connected" || status == "connecting") -> render(
                state = Tile.STATE_UNAVAILABLE,
                subtitle = "Активен локальный прокси",
            )

            status == "connected" -> render(
                state = Tile.STATE_ACTIVE,
                subtitle = targetName ?: "VPN включён",
            )

            status == "connecting" -> render(
                state = Tile.STATE_ACTIVE,
                subtitle = "Подключение…",
            )

            status == "disconnecting" -> stopVpn()

            status == "error" -> render(
                state = Tile.STATE_INACTIVE,
                subtitle = if (savedVpn == null) {
                    "Сначала подключись в приложении"
                } else {
                    "Ошибка · нажми повторить"
                },
            )

            else -> render(
                state = Tile.STATE_INACTIVE,
                subtitle = if (savedVpn == null) {
                    "Сначала подключись в приложении"
                } else {
                    "Нажми, чтобы включить"
                },
            )
        }
    }

    private fun render(state: Int, subtitle: String) {
        val tile = qsTile ?: return
        tile.label = "OrexRay VPN"
        tile.state = state
        tile.contentDescription = "OrexRay VPN. $subtitle"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = subtitle
        }
        tile.updateTile()
    }
}
