package ru.orex.ray

import android.os.Process
import java.util.ArrayDeque

internal object OrexRayDiagnosticsStore {
    private const val MAX_LINES = 100
    private val logs = ArrayDeque<String>()

    @Volatile var lastError: String? = null
    @Volatile var lastExitCode: Long? = null
    @Volatile var automaticRestarts: Int = 0
    @Volatile var coreRunning: Boolean = false

    @Synchronized
    fun log(line: String) {
        val clean = sanitize(line.trim())
        if (clean.isEmpty()) return
        logs.addLast(clean)
        while (logs.size > MAX_LINES) logs.removeFirst()
    }

    @Synchronized
    fun snapshot(): Map<String, Any?> = mapOf(
        "pid" to Process.myPid(),
        "coreRunning" to coreRunning,
        "lastError" to lastError?.let(::sanitize),
        "lastExitCode" to lastExitCode,
        "automaticRestarts" to automaticRestarts,
        "logs" to logs.toList(),
    )

    private fun sanitize(value: String): String = value
        .replace(
            Regex("\\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\\b"),
            "<UUID>",
        )
        .replace(Regex("vless://\\S+"), "vless://<REDACTED>")
}
