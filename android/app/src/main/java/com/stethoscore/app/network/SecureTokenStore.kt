package com.stethoscore.app.network

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-GCM ciphertext in private preferences; its key never leaves Android Keystore. */
class SecureTokenStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun save(token: String) {
        require(token.isNotBlank() && token.length <= 16_384 && token.none { it.code < 32 || it.code == 127 }) { "Invalid session token." }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
        cipher.updateAAD(KEY_ALIAS.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        val saved = prefs.edit()
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .commit()
        check(saved) { "The session token could not be saved." }
    }

    @Synchronized
    fun read(): String? {
        val encoded = prefs.getString("ciphertext", null) ?: return null
        val nonce = prefs.getString("iv", null) ?: return null
        return try {
            val secret = key(create = false) ?: return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, Base64.decode(nonce, Base64.NO_WRAP)))
            cipher.updateAAD(KEY_ALIAS.toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) {
            // A restored preference file without this device's key cannot sign in.
            // Never fall back to plaintext or return corrupted credentials.
            null
        }
    }

    @Synchronized
    fun clear() {
        check(prefs.edit().clear().commit()) { "The saved token could not be cleared." }
    }

    private fun key(create: Boolean): SecretKey? = synchronized(KEY_LOCK) {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return@synchronized it }
        if (!create) return@synchronized null
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build())
        generator.generateKey()
    }

    companion object {
        const val PREFS_NAME = "stethoscore_credentials"
        private const val KEY_ALIAS = "stethoscore.session.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private val KEY_LOCK = Any()
    }
}
