package ru.orex.ray

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import io.flutter.plugin.common.EventChannel

object OrexRayTunnelEvents {
    internal const val ACTION_RUNTIME_EVENT = "ru.orex.ray.action.RUNTIME_EVENT"
    private const val EXTRA_EVENT = "runtime_event"

    private var sink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var receiverContext: Context? = null

    @Volatile
    var lastEvent: Map<String, Any?> = event(status = "disconnected")
        private set

    @Synchronized
    fun attach(context: Context, eventSink: EventChannel.EventSink) {
        detach()
        val appContext = context.applicationContext
        sink = eventSink
        val nextReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val bundle = intent?.eventBundle() ?: return
                val value = fromBundle(bundle)
                lastEvent = value
                synchronized(this@OrexRayTunnelEvents) { sink }?.success(value)
            }
        }
        receiver = nextReceiver
        receiverContext = appContext
        val filter = IntentFilter(ACTION_RUNTIME_EVENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(
                nextReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(nextReceiver, filter)
        }
        // Initial state is queried explicitly through the service. Emitting a
        // persisted value here would briefly resurrect stale `connected` state
        // after the :vpn process was killed.
    }

    @Synchronized
    fun detach() {
        val currentReceiver = receiver
        val context = receiverContext
        receiver = null
        receiverContext = null
        sink = null
        if (currentReceiver != null && context != null) {
            runCatching { context.unregisterReceiver(currentReceiver) }
        }
    }

    fun emit(context: Context, value: Map<String, Any?>) {
        OrexRayRuntimeStateStore.save(context, value)
        emitTransient(context, value)
    }

    fun emitTransient(context: Context, value: Map<String, Any?>) {
        lastEvent = value
        context.sendBroadcast(
            Intent(ACTION_RUNTIME_EVENT)
                .setPackage(context.packageName)
                .putExtra(EXTRA_EVENT, toBundle(value)),
        )
    }

    internal fun toBundle(value: Map<String, Any?>): Bundle = Bundle().apply {
        putString("status", value["status"] as? String ?: "disconnected")
        putString("mode", value["mode"] as? String ?: OrexRayVpnService.MODE_VPN)
        putNullableString("targetId", value["targetId"] as? String)
        putNullableString("message", value["message"] as? String)
        putNullableString("errorMessage", value["errorMessage"] as? String)
        putLong("downloadBytes", (value["downloadBytes"] as? Number)?.toLong() ?: 0L)
        putLong("uploadBytes", (value["uploadBytes"] as? Number)?.toLong() ?: 0L)
        putLong(
            "downloadBytesPerSecond",
            (value["downloadBytesPerSecond"] as? Number)?.toLong() ?: 0L,
        )
        putLong(
            "uploadBytesPerSecond",
            (value["uploadBytesPerSecond"] as? Number)?.toLong() ?: 0L,
        )
        putLong("durationSeconds", (value["durationSeconds"] as? Number)?.toLong() ?: 0L)
        val latency = (value["latencyMs"] as? Number)?.toInt()
        if (latency == null) remove("latencyMs") else putInt("latencyMs", latency)
        putString("pingStatus", value["pingStatus"] as? String ?: "unknown")
        putNullableString(
            "activeBalancerMemberId",
            value["activeBalancerMemberId"] as? String,
        )
    }

    internal fun fromBundle(bundle: Bundle): Map<String, Any?> = event(
        status = bundle.getString("status") ?: "disconnected",
        mode = bundle.getString("mode") ?: OrexRayVpnService.MODE_VPN,
        targetId = bundle.getString("targetId"),
        message = bundle.getString("message"),
        errorMessage = bundle.getString("errorMessage"),
        downloadBytes = bundle.getLong("downloadBytes"),
        uploadBytes = bundle.getLong("uploadBytes"),
        downloadBytesPerSecond = bundle.getLong("downloadBytesPerSecond"),
        uploadBytesPerSecond = bundle.getLong("uploadBytesPerSecond"),
        durationSeconds = bundle.getLong("durationSeconds"),
        latencyMs = if (bundle.containsKey("latencyMs")) bundle.getInt("latencyMs") else null,
        pingStatus = bundle.getString("pingStatus") ?: "unknown",
        activeBalancerMemberId = bundle.getString("activeBalancerMemberId"),
    )

    private fun Intent.eventBundle(): Bundle? = if (Build.VERSION.SDK_INT >= 33) {
        getBundleExtra(EXTRA_EVENT)
    } else {
        @Suppress("DEPRECATION")
        getBundleExtra(EXTRA_EVENT)
    }

    private fun Bundle.putNullableString(key: String, value: String?) {
        if (value == null) remove(key) else putString(key, value)
    }

    fun event(
        status: String,
        mode: String = "vpn_tun",
        targetId: String? = null,
        message: String? = null,
        errorMessage: String? = null,
        downloadBytes: Long = 0,
        uploadBytes: Long = 0,
        downloadBytesPerSecond: Long = 0,
        uploadBytesPerSecond: Long = 0,
        durationSeconds: Long = 0,
        latencyMs: Int? = null,
        pingStatus: String = "unknown",
        activeBalancerMemberId: String? = null,
    ): Map<String, Any?> = mapOf(
        "status" to status,
        "mode" to mode,
        "targetId" to targetId,
        "message" to message,
        "errorMessage" to errorMessage,
        "downloadBytes" to downloadBytes,
        "uploadBytes" to uploadBytes,
        "downloadBytesPerSecond" to downloadBytesPerSecond,
        "uploadBytesPerSecond" to uploadBytesPerSecond,
        "durationSeconds" to durationSeconds,
        "latencyMs" to latencyMs,
        "pingStatus" to pingStatus,
        "activeBalancerMemberId" to activeBalancerMemberId,
    )
}
