package kz.joba.services_marketplace

import android.os.Build
import androidx.biometric.BiometricPrompt
import androidx.biometric.BiometricManager
import androidx.core.content.ContextCompat
import javax.crypto.Cipher
import java.security.SecureRandom
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKeyFactory

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "joba.device_security")
            .setMethodCallHandler { call, result ->
                if (call.method != "hardwareBacked") {
                    biometry(call.method, call.argument<String>("alias") ?: "", call.argument<String>("title")?.take(100) ?: "JOBA", call.argument<String>("cancel")?.take(40) ?: "Cancel", result)
                    return@setMethodCallHandler
                }
                val alias = "joba-security-probe"
                try {
                    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                    generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
                    val key = generator.generateKey()
                    val info = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore").getKeySpec(key, KeyInfo::class.java) as KeyInfo
                    @Suppress("DEPRECATION")
                    result.success(info.isInsideSecureHardware)
                } catch (_: Exception) { result.success(false) }
                finally { try { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias) } catch (_: Exception) {} }
            }
    }
    private fun biometry(method: String, alias: String, title: String, cancel: String, result: MethodChannel.Result) {
        if (!alias.matches(Regex("joba\\.biometry\\.[0-9a-f]{64}"))) { result.error("INVALID_KEY", "Invalid local key", null); return }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        try {
            if (method == "clearBiometry") { store.deleteEntry(alias); result.success(true); return }
            if (method == "enableBiometry") {
                if (Build.VERSION.SDK_INT < 24) { result.error("BIOMETRY_UNAVAILABLE", "Используйте PIN или пароль", null); return }
                if (BiometricManager.from(this).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) != BiometricManager.BIOMETRIC_SUCCESS) {
                    result.error("BIOMETRY_UNAVAILABLE", "Сильная биометрия недоступна", null); return
                }
                val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setUserAuthenticationRequired(true).setInvalidatedByBiometricEnrollment(true)
                if (Build.VERSION.SDK_INT >= 30) spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                else spec.setUserAuthenticationValidityDurationSeconds(-1)
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(spec.build()); generateKey() }
                result.success(true); return
            }
            val key = store.getKey(alias, null) as? javax.crypto.SecretKey
            if (key == null) { result.error("BIOMETRY_CHANGED", "Войдите снова с паролем", null); return }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            try { cipher.init(Cipher.ENCRYPT_MODE, key) }
            catch (e: UserNotAuthenticatedException) { if (method == "checkBiometry") { result.success(true); return } else throw e }
            if (method == "checkBiometry") { result.success(true); return }
            if (method != "unlockBiometry") { result.notImplemented(); return }
            val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object: BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(code: Int, message: CharSequence) { result.success(false) }
                override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                    try {
                        val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
                        result.success(auth.cryptoObject?.cipher?.doFinal(challenge)?.isNotEmpty() == true)
                    } catch (_: Exception) { result.error("BIOMETRY_CHANGED", "Войдите снова с паролем", null) }
                }
            })
            val info = BiometricPrompt.PromptInfo.Builder().setTitle(title)
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG).setNegativeButtonText(cancel).build()
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (_: KeyPermanentlyInvalidatedException) { result.error("BIOMETRY_CHANGED", "Биометрия изменилась. Войдите снова с паролем", null) }
        catch (_: Exception) { result.error("BIOMETRY_UNAVAILABLE", "Биометрия недоступна", null) }
    }
}
