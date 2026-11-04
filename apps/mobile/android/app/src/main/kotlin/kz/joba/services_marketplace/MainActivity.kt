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
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        NativeCrashSpool.install(applicationContext)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager=getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.createNotificationChannel(android.app.NotificationChannel("joba_events", "Сообщения и события JOBA", android.app.NotificationManager.IMPORTANCE_HIGH))
        }
    }
    private var locationResult: MethodChannel.Result? = null
    private val locationRequest = 18035
    private val locationHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val locationSignals = mutableListOf<androidx.core.os.CancellationSignal>()
    private var locationDeadline: Runnable? = null

    private fun finishLocation(result: MethodChannel.Result, location: android.location.Location?, code: String = "LOCATION_UNAVAILABLE") {
        if (locationResult !== result) return
        locationResult = null
        locationDeadline?.let { locationHandler.removeCallbacks(it) }
        locationDeadline = null
        locationSignals.forEach { try { it.cancel() } catch (_: Exception) {} }
        locationSignals.clear()
        if (location == null) result.error(code, "Не удалось определить местоположение. Выберите точку на карте.", null)
        else result.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude, "accuracy" to location.accuracy))
    }

    private fun locate(result: MethodChannel.Result) {
        if (locationResult != null) { result.error("LOCATION_BUSY", "Определение местоположения уже выполняется", null); return }
        locationResult = result
        locationDeadline = Runnable { finishLocation(result, null) }.also { locationHandler.postDelayed(it, 40000) }
        try {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                androidx.core.app.ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION), locationRequest)
            } else readLocation()
        } catch (_: Exception) { finishLocation(result, null) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grants)
        if (requestCode == locationRequest) {
            if (grants.any { it == android.content.pm.PackageManager.PERMISSION_GRANTED }) readLocation()
            else locationResult?.let { finishLocation(it, null, "GPS_DENIED") }
        }
    }

    private fun readLocation() {
        val result = locationResult ?: return
        try {
            val manager = getSystemService(android.content.Context.LOCATION_SERVICE) as android.location.LocationManager
            val fine = ContextCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val providers = listOf(android.location.LocationManager.NETWORK_PROVIDER, android.location.LocationManager.GPS_PROVIDER)
                .filter { (it != android.location.LocationManager.GPS_PROVIDER || fine) && manager.isProviderEnabled(it) }
            if (providers.isEmpty()) { finishLocation(result, null); return }
            // Never use stale city/country coordinates as the device position.
            val cached = providers.mapNotNull { provider ->
                try { manager.getLastKnownLocation(provider) } catch (_: Exception) { null }
            }.filter {
                val age = (android.os.SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) / 1000000
                age in 0..120000 && it.hasAccuracy() && it.accuracy <= 5000 && validLocation(it)
            }.minByOrNull { it.accuracy }
            if (cached != null && cached.accuracy <= 200 && (android.os.SystemClock.elapsedRealtimeNanos() - cached.elapsedRealtimeNanos) / 1000000 <= 30000) {
                finishLocation(result, cached); return
            }
            locationDeadline?.let { locationHandler.removeCallbacks(it) }
            locationDeadline = Runnable { finishLocation(result, cached) }.also { locationHandler.postDelayed(it, 15000) }
            var remaining = providers.size
            // Race network and GPS: GPS may never get a fix indoors. A null
            // response from either provider must not discard the other request.
            for (provider in providers) {
                if (locationResult !== result) break
                val cancellation = androidx.core.os.CancellationSignal()
                locationSignals.add(cancellation)
                try {
                    androidx.core.location.LocationManagerCompat.getCurrentLocation(manager, provider, cancellation, ContextCompat.getMainExecutor(this)) { location ->
                        if (locationResult === result) {
                            remaining--
                            if (location != null && validLocation(location)) finishLocation(result, location)
                            else if (remaining == 0) finishLocation(result, cached)
                        }
                    }
                } catch (_: Exception) {
                    remaining--
                    if (remaining == 0) finishLocation(result, cached)
                }
            }
        } catch (_: Exception) { finishLocation(result, null) }
    }

    private fun validLocation(location: android.location.Location): Boolean =
        location.latitude.isFinite() && location.longitude.isFinite() &&
            location.latitude in -90.0..90.0 && location.longitude in -180.0..180.0

    override fun onDestroy() {
        locationResult?.let { finishLocation(it, null, "LOCATION_CANCELLED") }
        super.onDestroy()
    }
    private var exportResult: MethodChannel.Result? = null
    private var exportSource: java.io.File? = null
    private val exportRequest = 18034
    private fun saveExport(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") { result.notImplemented(); return }
        if (exportResult != null) { result.error("EXPORT_BUSY", "Another export is active", null); return }
        if (!lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) { result.error("EXPORT_UNAVAILABLE", "Open the application to save the export", null); return }
        try {
            val file = java.io.File(call.argument<String>("path") ?: "").canonicalFile
            if (!file.isFile || !file.path.startsWith(cacheDir.canonicalPath + java.io.File.separator)) {
                result.error("EXPORT_INVALID", "Invalid private export file", null); return
            }
            exportSource = file; exportResult = result
            val name = (call.argument<String>("filename") ?: "joba-export.zip").take(80).replace(Regex("[^A-Za-z0-9._-]"), "_")
            val intent = android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(android.content.Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(android.content.Intent.EXTRA_TITLE, name)
            }
            startActivityForResult(intent, exportRequest)
        } catch (_: Exception) { exportResult = null; exportSource = null; result.error("EXPORT_UNAVAILABLE", "File save dialog is unavailable", null) }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (requestCode != exportRequest) { super.onActivityResult(requestCode, resultCode, data); return }
        val result = exportResult ?: return
        val source = exportSource
        exportResult = null; exportSource = null
        val target = data?.data
        if (resultCode != android.app.Activity.RESULT_OK || target == null || source == null) { result.success(false); return }
        Thread {
            try {
                source.inputStream().use { input ->
                    val destination = contentResolver.openOutputStream(target, "wt") ?: throw java.io.IOException("Destination unavailable")
                    destination.use { output -> input.copyTo(output); output.flush() }
                }
                runOnUiThread { result.success(true) }
            } catch (_: Exception) { runOnUiThread { result.error("EXPORT_SAVE_FAILED", "File could not be saved", null) } }
        }.start()
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "joba.runtime").setMethodCallHandler { call, result ->
            try { when (call.method) {
                "info" -> { result.success(NativeCrashSpool.info(applicationContext)); return@setMethodCallHandler }
                "installCrashHandler" -> { NativeCrashSpool.install(applicationContext); result.success(null); return@setMethodCallHandler }
                "screen" -> { NativeCrashSpool.screen(applicationContext, call.argument<String>("screen") ?: "unknown"); result.success(null); return@setMethodCallHandler }
                "pendingCrashes" -> { result.success(NativeCrashSpool.pending(applicationContext)); return@setMethodCallHandler }
                "ackCrash" -> { try { NativeCrashSpool.acknowledge(applicationContext, call.argument<String>("id") ?: "") } catch (_: Exception) {} ; result.success(null); return@setMethodCallHandler }
                "ackExit" -> { val timestamp = call.argument<Number>("timestamp")?.toLong() ?: 0L; val prefs = getSharedPreferences("joba-runtime", MODE_PRIVATE); if(timestamp > prefs.getLong("last-exit", 0L))prefs.edit().putLong("last-exit", timestamp).commit(); result.success(null); return@setMethodCallHandler }
            }
            } catch (_: Exception) { result.error("DIAGNOSTIC_UNAVAILABLE", "Диагностика временно недоступна", null); return@setMethodCallHandler }
            if (call.method != "previousExits") { result.notImplemented(); return@setMethodCallHandler }
            try {
                if (Build.VERSION.SDK_INT < 30) { result.success(emptyList<Map<String, Any>>()); return@setMethodCallHandler }
                val preferences = getSharedPreferences("joba-runtime", MODE_PRIVATE)
                val seen = preferences.getLong("last-exit", 0L)
                val manager = getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val exits = manager.getHistoricalProcessExitReasons(packageName, 0, 5)
                val recent = exits.filter { it.timestamp > seen && it.timestamp > System.currentTimeMillis() - 7 * 86400000L }
                result.success(recent.filter { it.reason in listOf(2, 3, 4, 5, 6, 7, 9) }.map {
                    var seed = preferences.getString("diagnostic-seed", null)
                    if(seed == null){seed=java.util.UUID.randomUUID().toString();preferences.edit().putString("diagnostic-seed", seed).commit()}
                    mapOf("id" to java.util.UUID.nameUUIDFromBytes((seed + ":" + it.timestamp + ":" + it.reason).toByteArray()).toString(), "reason" to it.reason, "status" to it.status, "timestamp" to it.timestamp, "pss_kb" to it.pss, "rss_kb" to it.rss, "screen" to (preferences.getString("screen", "unknown") ?: "unknown"))
                })
            } catch (_: Exception) { result.success(emptyList<Map<String, Any>>()) }
        }

        MethodChannel(engine.dartExecutor.binaryMessenger,"joba.location").setMethodCallHandler {call,result->
            if(call.method=="current")locate(result) else result.notImplemented()
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "joba.share").setMethodCallHandler { call, result ->
            if (call.method != "text") { result.notImplemented() }
            else {
                val text = call.argument<String>("text")
                if (text.isNullOrBlank() || text.length > 2000) { result.error("SHARE_INVALID", "Invalid invitation", null) }
                else try {
                    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                        type = "text/plain"; putExtra(android.content.Intent.EXTRA_TEXT, text)
                    }
                    startActivity(android.content.Intent.createChooser(intent, null)); result.success(null)
                } catch (error: Exception) { result.error("SHARE_UNAVAILABLE", "Sharing is unavailable", null) }
            }
        }

        MethodChannel(engine.dartExecutor.binaryMessenger, "joba.file_export").setMethodCallHandler { call, result -> saveExport(call, result) }
        MethodChannel(engine.dartExecutor.binaryMessenger, "joba.device_security")
            .setMethodCallHandler { call, result ->
                if (call.method != "hardwareBacked" && call.method != "secureStorageAvailable") {
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
                    result.success(call.method == "secureStorageAvailable" || info.isInsideSecureHardware)
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
