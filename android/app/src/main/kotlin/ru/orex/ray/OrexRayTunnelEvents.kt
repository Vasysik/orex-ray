package ru.orex.ray

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
    fun attach(eventSink: EventChannel.EventSink) {
        sink = eventSink
        eventSink.success(lastEvent)
    }

    @Synchronized
    fun detach() {
        sink = null
    }

    fun emit(value: Map<String, Any?>) {
        lastEvent = value
        mainHandler.post {
            synchronized(this) {
                sink?.success(value)
            }
        }
    }

    fun event(
        status: String,
        mode: String = "vpn_tun",
        message: String? = null,
        errorMessage: String? = null,
        downloadBytes: Long = 0,
        uploadBytes: Long = 0,
        durationSeconds: Long = 0,
    ): Map<String, Any?> = mapOf(
        "status" to status,
        "mode" to mode,
        "message" to message,
        "errorMessage" to errorMessage,
        "downloadBytes" to downloadBytes,
        "uploadBytes" to uploadBytes,
        "durationSeconds" to durationSeconds,
    )
}
