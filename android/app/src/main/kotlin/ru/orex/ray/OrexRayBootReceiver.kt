package ru.orex.ray

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log

class OrexRayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!OrexRayStartupStore.autoConnectOnBoot(context)) return
        if (VpnService.prepare(context) != null) {
            Log.w("OrexRay", "Boot auto-connect skipped: VPN permission is not granted")
            return
        }
        val startIntent = OrexRayStartIntentStore.loadQuickTileVpn(context) ?: return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(startIntent)
            } else {
                context.startService(startIntent)
            }
        }.onFailure { Log.e("OrexRay", "Boot auto-connect failed", it) }
    }
}
