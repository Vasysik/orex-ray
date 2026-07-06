package ru.orex.ray

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * Native, translucent permission bridge used only by the Quick Settings tile.
 * Flutter does not need to be started just to grant VPN consent.
 */
class OrexRayVpnPermissionActivity : Activity() {
    companion object {
        private const val TAG = "OrexRay"
        private const val VPN_PERMISSION_REQUEST = 7733
    }

    private var startIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startIntent = OrexRayStartIntentStore.loadQuickTileVpn(this)
        if (startIntent == null) {
            openAppAndFinish()
            return
        }
        continuePermissionFlow()
    }

    private fun continuePermissionFlow() {
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            @Suppress("DEPRECATION")
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }

        startVpnAndFinish()
    }

    @Deprecated("The platform callback is required for the VPN permission activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return

        if (resultCode == RESULT_OK) {
            startVpnAndFinish()
        } else {
            OrexRayTunnelEvents.emit(
                OrexRayTunnelEvents.event(
                    status = "error",
                    mode = OrexRayVpnService.MODE_VPN,
                    errorMessage = "Разрешение VPN не выдано",
                ),
            )
            OrexRayQuickSettingsTileService.requestRefresh(this)
            finishWithoutAnimation()
        }
    }

    private fun startVpnAndFinish() {
        val intent = startIntent ?: OrexRayStartIntentStore.loadQuickTileVpn(this)
        if (intent == null) {
            openAppAndFinish()
            return
        }

        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        }.onFailure {
            Log.e(TAG, "Could not start VPN after Quick Settings permission flow", it)
            OrexRayTunnelEvents.emit(
                OrexRayTunnelEvents.event(
                    status = "error",
                    mode = OrexRayVpnService.MODE_VPN,
                    errorMessage = it.message ?: it.javaClass.simpleName,
                ),
            )
            OrexRayQuickSettingsTileService.requestRefresh(this)
        }
        finishWithoutAnimation()
    }

    private fun openAppAndFinish() {
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        finishWithoutAnimation()
    }

    private fun finishWithoutAnimation() {
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
