package ru.orex.ray

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object OrexRayTunnelEvents {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    @Volatile
    var lastEvent: Map<String, Any?> = event(status = "disconnected")
        private set

    @Synchronized
    fun attach(context: Context, eventSink: EventChannel.EventSink) {
        lastEvent = OrexRayVpnService.runtimeState(context)
        sink = eventSink
        eventSink.success(lastEvent)
    }

    @Synchronized
    fun detach() {
        sink = null
    }

    fun emit(context: Context, value: Map<String, Any?>) {
        OrexRayRuntimeStateStore.save(context, value)
        lastEvent = value
        val eventSink = synchronized(this) { sink } ?: return
        mainHandler.post {
            synchronized(this) {
                if (sink === eventSink) eventSink.success(value)
            }
        }
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
    )
}
