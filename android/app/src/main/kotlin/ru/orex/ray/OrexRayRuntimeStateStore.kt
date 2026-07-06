package ru.orex.ray

import android.content.Context

/**
 * Stores the last coarse tunnel state outside the process.
 *
 * Quick Settings tiles can be rebound in a fresh process after the foreground
 * VPN service stops. Keeping the state only in OrexRayTunnelEvents would leave
 * a transient unavailable tile stuck until the Flutter activity starts again.
 */
internal object OrexRayRuntimeStateStore {
    private const val PREFERENCES = "orex_ray_runtime_state_v1"
    private const val KEY_STATUS = "status"
    private const val KEY_MODE = "mode"
    private const val KEY_MESSAGE = "message"
    private const val KEY_ERROR = "error"

    fun load(context: Context): Map<String, Any?> {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        return OrexRayTunnelEvents.event(
            status = preferences.getString(KEY_STATUS, "disconnected") ?: "disconnected",
            mode = preferences.getString(KEY_MODE, OrexRayVpnService.MODE_VPN)
                ?: OrexRayVpnService.MODE_VPN,
            message = preferences.getString(KEY_MESSAGE, null),
            errorMessage = preferences.getString(KEY_ERROR, null),
        )
    }

    fun save(context: Context, value: Map<String, Any?>) {
        val status = value["status"] as? String ?: "disconnected"
        val mode = value["mode"] as? String ?: OrexRayVpnService.MODE_VPN
        val message = value["message"] as? String
        val error = value["errorMessage"] as? String
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

        if (
            preferences.getString(KEY_STATUS, null) == status &&
            preferences.getString(KEY_MODE, null) == mode &&
            status == "connected"
        ) {
            return
        }

        // commit() is deliberate here: disconnect is followed by stopSelf(), so
        // the new state must reach disk before Android tears the process down.
        preferences.edit()
            .putString(KEY_STATUS, status)
            .putString(KEY_MODE, mode)
            .apply {
                if (message == null) remove(KEY_MESSAGE) else putString(KEY_MESSAGE, message)
                if (error == null) remove(KEY_ERROR) else putString(KEY_ERROR, error)
            }
            .commit()
    }
}
