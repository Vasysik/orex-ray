package ru.orex.ray

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists service start intents in the Android keystore-backed secure store.
 *
 * Restart state is short-lived and is removed on a normal disconnect. Quick
 * Settings state intentionally survives disconnects so the tile can reconnect
 * the last VPN that was successfully started from the app.
 */
internal object OrexRayStartIntentStore {
    private const val TAG = "OrexRay"
    private const val RESTART_STATE_KEY = "service_restart_state_v1"
    private const val QUICK_TILE_STATE_KEY = "quick_tile_start_state_v1"

    fun saveRestart(context: Context, intent: Intent) {
        save(context, RESTART_STATE_KEY, intent, restartServiceOverride = true)
    }

    fun loadRestart(context: Context): Intent? = load(context, RESTART_STATE_KEY)

    fun clearRestart(context: Context) {
        clear(context, RESTART_STATE_KEY)
    }

    fun saveQuickTileVpn(context: Context, intent: Intent) {
        if (intent.getStringExtra(OrexRayVpnService.EXTRA_MODE) != OrexRayVpnService.MODE_VPN) {
            return
        }
        save(context, QUICK_TILE_STATE_KEY, intent)
    }

    fun loadQuickTileVpn(context: Context): Intent? {
        val intent = load(context, QUICK_TILE_STATE_KEY) ?: return null
        return intent.takeIf {
            it.getStringExtra(OrexRayVpnService.EXTRA_MODE) == OrexRayVpnService.MODE_VPN
        }
    }

    fun updateRestartMetadata(context: Context, targetName: String, latencyMs: Int?) {
        updateMetadata(context, RESTART_STATE_KEY, targetName, latencyMs)
    }

    fun updateQuickTileMetadata(context: Context, targetName: String, latencyMs: Int?) {
        updateMetadata(context, QUICK_TILE_STATE_KEY, targetName, latencyMs)
    }

    private fun save(
        context: Context,
        key: String,
        intent: Intent,
        restartServiceOverride: Boolean? = null,
    ) {
        val json = JSONObject()
            .put(
                OrexRayVpnService.EXTRA_CONFIG,
                intent.getStringExtra(OrexRayVpnService.EXTRA_CONFIG).orEmpty(),
            )
            .put(
                OrexRayVpnService.EXTRA_MODE,
                intent.getStringExtra(OrexRayVpnService.EXTRA_MODE).orEmpty(),
            )
            .put(
                OrexRayVpnService.EXTRA_TARGET_NAME,
                intent.getStringExtra(OrexRayVpnService.EXTRA_TARGET_NAME).orEmpty(),
            )
            .put(
                OrexRayVpnService.EXTRA_LATENCY_MS,
                intent.getIntExtra(OrexRayVpnService.EXTRA_LATENCY_MS, -1),
            )
            .put(
                OrexRayVpnService.EXTRA_MTU,
                intent.getIntExtra(OrexRayVpnService.EXTRA_MTU, 1500),
            )
            .put(
                OrexRayVpnService.EXTRA_SOCKS_PORT,
                intent.getIntExtra(OrexRayVpnService.EXTRA_SOCKS_PORT, 20808),
            )
            .put(
                OrexRayVpnService.EXTRA_HTTP_PORT,
                intent.getIntExtra(OrexRayVpnService.EXTRA_HTTP_PORT, 20809),
            )
            .put(
                OrexRayVpnService.EXTRA_LOCAL_PROXY_IN_VPN,
                intent.getBooleanExtra(OrexRayVpnService.EXTRA_LOCAL_PROXY_IN_VPN, true),
            )
            .put(
                OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS,
                intent.getIntExtra(OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS, 2),
            )
            .put(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED,
                intent.getBooleanExtra(OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED, true),
            )
            .put(
                OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_PING,
                intent.getBooleanExtra(OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_PING, true),
            )
            .put(
                OrexRayVpnService.EXTRA_RESTART_SERVICE,
                restartServiceOverride
                    ?: intent.getBooleanExtra(OrexRayVpnService.EXTRA_RESTART_SERVICE, true),
            )
            .put(
                OrexRayVpnService.EXTRA_APP_ROUTING_MODE,
                intent.getStringExtra(OrexRayVpnService.EXTRA_APP_ROUTING_MODE).orEmpty(),
            )
            .put(
                OrexRayVpnService.EXTRA_STATS_OUTBOUND_TAGS,
                JSONArray(
                    intent.getStringArrayListExtra(OrexRayVpnService.EXTRA_STATS_OUTBOUND_TAGS)
                        .orEmpty(),
                ),
            )
            .put(
                OrexRayVpnService.EXTRA_DNS_SERVERS,
                JSONArray(
                    intent.getStringArrayListExtra(OrexRayVpnService.EXTRA_DNS_SERVERS).orEmpty(),
                ),
            )
            .put(
                OrexRayVpnService.EXTRA_APP_PACKAGES,
                JSONArray(
                    intent.getStringArrayListExtra(OrexRayVpnService.EXTRA_APP_PACKAGES).orEmpty(),
                ),
            )

        AndroidSecureStore(context.applicationContext).write(key, json.toString())
    }

    private fun load(context: Context, key: String): Intent? {
        val secureStore = AndroidSecureStore(context.applicationContext)
        val payload = runCatching { secureStore.read(key) }
            .onFailure { Log.e(TAG, "Could not read encrypted start state: $key", it) }
            .getOrNull()
            ?: return null

        return runCatching {
            val json = JSONObject(payload)
            val config = json.optString(OrexRayVpnService.EXTRA_CONFIG)
            if (config.isBlank()) return@runCatching null

            Intent(context, OrexRayVpnService::class.java)
                .setAction(OrexRayVpnService.ACTION_START)
                .putExtra(OrexRayVpnService.EXTRA_CONFIG, config)
                .putExtra(
                    OrexRayVpnService.EXTRA_MODE,
                    json.optString(OrexRayVpnService.EXTRA_MODE, OrexRayVpnService.MODE_VPN),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_TARGET_NAME,
                    json.optString(OrexRayVpnService.EXTRA_TARGET_NAME, "OrexRay"),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_LATENCY_MS,
                    json.optInt(OrexRayVpnService.EXTRA_LATENCY_MS, -1),
                )
                .putStringArrayListExtra(
                    OrexRayVpnService.EXTRA_STATS_OUTBOUND_TAGS,
                    json.optJSONArray(OrexRayVpnService.EXTRA_STATS_OUTBOUND_TAGS)
                        .toStringArrayList(),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_MTU,
                    json.optInt(OrexRayVpnService.EXTRA_MTU, 1500),
                )
                .putStringArrayListExtra(
                    OrexRayVpnService.EXTRA_DNS_SERVERS,
                    json.optJSONArray(OrexRayVpnService.EXTRA_DNS_SERVERS).toStringArrayList(),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_SOCKS_PORT,
                    json.optInt(OrexRayVpnService.EXTRA_SOCKS_PORT, 20808),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_HTTP_PORT,
                    json.optInt(OrexRayVpnService.EXTRA_HTTP_PORT, 20809),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_LOCAL_PROXY_IN_VPN,
                    json.optBoolean(OrexRayVpnService.EXTRA_LOCAL_PROXY_IN_VPN, true),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS,
                    json.optInt(OrexRayVpnService.EXTRA_STATS_INTERVAL_SECONDS, 2),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED,
                    json.optBoolean(OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_SPEED, true),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_PING,
                    json.optBoolean(OrexRayVpnService.EXTRA_SHOW_NOTIFICATION_PING, true),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_RESTART_SERVICE,
                    json.optBoolean(OrexRayVpnService.EXTRA_RESTART_SERVICE, true),
                )
                .putExtra(
                    OrexRayVpnService.EXTRA_APP_ROUTING_MODE,
                    json.optString(OrexRayVpnService.EXTRA_APP_ROUTING_MODE, "all"),
                )
                .putStringArrayListExtra(
                    OrexRayVpnService.EXTRA_APP_PACKAGES,
                    json.optJSONArray(OrexRayVpnService.EXTRA_APP_PACKAGES).toStringArrayList(),
                )
        }.onFailure {
            Log.e(TAG, "Encrypted start state is invalid: $key", it)
            runCatching { secureStore.delete(key) }
        }.getOrNull()
    }

    private fun updateMetadata(
        context: Context,
        key: String,
        targetName: String,
        latencyMs: Int?,
    ) {
        val secureStore = AndroidSecureStore(context.applicationContext)
        val payload = runCatching { secureStore.read(key) }.getOrNull() ?: return
        runCatching {
            val json = JSONObject(payload)
                .put(OrexRayVpnService.EXTRA_TARGET_NAME, targetName)
                .put(OrexRayVpnService.EXTRA_LATENCY_MS, latencyMs ?: -1)
            secureStore.write(key, json.toString())
        }.onFailure { Log.w(TAG, "Could not update encrypted start metadata: $key", it) }
    }

    private fun clear(context: Context, key: String) {
        runCatching { AndroidSecureStore(context.applicationContext).delete(key) }
            .onFailure { Log.w(TAG, "Could not clear encrypted start state: $key", it) }
    }

    private fun JSONArray?.toStringArrayList(): ArrayList<String> {
        if (this == null) return arrayListOf()
        val values = ArrayList<String>(length())
        for (index in 0 until length()) {
            optString(index).takeIf { it.isNotBlank() }?.let(values::add)
        }
        return values
    }
}
