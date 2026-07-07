package ru.orex.ray

import android.content.Context

internal object OrexRayStartupStore {
    private const val FILE_NAME = "orexray_startup"
    private const val AUTO_CONNECT_BOOT_KEY = "auto_connect_on_boot"

    fun setAutoConnectOnBoot(context: Context, enabled: Boolean) {
        context.applicationContext
            .getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(AUTO_CONNECT_BOOT_KEY, enabled)
            .apply()
    }

    fun autoConnectOnBoot(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
            .getBoolean(AUTO_CONNECT_BOOT_KEY, false)
}
