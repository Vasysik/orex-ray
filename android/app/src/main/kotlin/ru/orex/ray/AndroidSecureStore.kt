package ru.orex.ray

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class AndroidSecureStore(
    context: Context,
    preferencesName: String = DEFAULT_PREFS_NAME,
) {
    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "orexray_secure_store_key_v1"
        internal const val DEFAULT_PREFS_NAME = "orexray_secure_store_v1"
        internal const val VPN_PREFS_NAME = "orexray_vpn_secure_store_v2"
        private const val IV_LENGTH_BYTES = 12
        private const val GCM_TAG_LENGTH_BITS = 128
    }

    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val secureRandom = SecureRandom()

    fun read(key: String): String? {
        validateKey(key)
        val encoded = preferences.getString(key, null) ?: return null
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        require(payload.size > IV_LENGTH_BYTES) { "Encrypted value is truncated" }

        val iv = payload.copyOfRange(0, IV_LENGTH_BYTES)
        val ciphertext = payload.copyOfRange(IV_LENGTH_BYTES, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateKey(),
            GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv),
        )
        cipher.updateAAD(key.toByteArray(StandardCharsets.UTF_8))
        return String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
    }

    fun write(key: String, value: String) {
        validateKey(key)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(key.toByteArray(StandardCharsets.UTF_8))
        val ciphertext = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val payload = ByteArray(cipher.iv.size + ciphertext.size)
        System.arraycopy(cipher.iv, 0, payload, 0, cipher.iv.size)
        System.arraycopy(ciphertext, 0, payload, cipher.iv.size, ciphertext.size)
        check(
            preferences.edit()
                .putString(key, Base64.encodeToString(payload, Base64.NO_WRAP))
                .commit(),
        ) { "Could not persist encrypted value" }
    }

    fun delete(key: String) {
        validateKey(key)
        check(preferences.edit().remove(key).commit()) {
            "Could not delete encrypted value"
        }
    }

    fun getOrCreateRandomUrlSafeToken(key: String, byteCount: Int): String {
        require(byteCount in 16..64) { "Token size is out of range" }
        read(key)?.let { existing ->
            val decoded = runCatching {
                Base64.decode(existing, Base64.NO_WRAP or Base64.URL_SAFE)
            }.getOrNull()
            if (decoded?.size == byteCount) return existing
        }

        val bytes = ByteArray(byteCount).also(secureRandom::nextBytes)
        val token = Base64.encodeToString(
            bytes,
            Base64.NO_PADDING or Base64.NO_WRAP or Base64.URL_SAFE,
        )
        write(key, token)
        return token
    }

    private fun validateKey(key: String) {
        require(key.matches(Regex("[a-zA-Z0-9_.-]{1,64}"))) { "Invalid secure storage key" }
    }

    @Synchronized
    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE,
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return keyGenerator.generateKey()
    }
}
