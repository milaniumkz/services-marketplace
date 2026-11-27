package kz.joba.services_marketplace

import android.content.Context
import android.os.Build
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Private, bounded disk spool. No account, token or form values are read. */
internal object NativeCrashSpool {
    private val lock = Any()
    private fun now(): String = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date())
    private var installed: Thread.UncaughtExceptionHandler? = null
    private val recording = ThreadLocal<Boolean>()
    private fun file(context: Context) = AtomicFile(File(context.filesDir, "joba-native-crashes.json"))
    private fun read(context: Context): JSONArray = try { JSONArray(String(file(context).readFully(), Charsets.UTF_8)) } catch (_: Exception) { JSONArray() }
    private fun write(context: Context, reports: JSONArray) {
        val target = file(context)
        val stream = target.startWrite()
        try { stream.write(reports.toString().toByteArray(Charsets.UTF_8)); target.finishWrite(stream) }
        catch (error: Exception) { target.failWrite(stream); throw error }
    }
    fun info(context: Context): Map<String, Any> {
        val pkg = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf("platform" to "android", "app_version" to (pkg.versionName ?: "unknown"),
            "build" to (if (Build.VERSION.SDK_INT >= 28) pkg.longVersionCode else @Suppress("DEPRECATION") pkg.versionCode.toLong()).toString(),
            "device_model" to (Build.MANUFACTURER + " " + Build.MODEL).take(120), "os_version" to Build.VERSION.RELEASE.take(80))
    }
    fun screen(context: Context, name: String) {
        if (!Regex("^[a-z][a-z0-9-]{0,63}$").matches(name)) return
        val prefs = context.getSharedPreferences("joba-runtime", Context.MODE_PRIVATE)
        val old = try { JSONArray(prefs.getString("breadcrumbs", "[]")) } catch (_: Exception) { JSONArray() }
        val next = JSONArray()
        for (i in maxOf(0, old.length() - 19) until old.length()) next.put(old.get(i))
        next.put(JSONObject(mapOf("screen" to name, "at" to now())))
        prefs.edit().putString("screen", name).putString("breadcrumbs", next.toString()).apply()
    }
    fun install(context: Context) {
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        if (previous === installed) return
        val handler = Thread.UncaughtExceptionHandler { thread, error ->
            val alreadyRecording = recording.get() == true
            recording.set(true)
            try {
                if (!alreadyRecording) try {
                    val prefs = app.getSharedPreferences("joba-runtime", Context.MODE_PRIVATE)
                    val report = JSONObject(info(app))
                    report.put("id", UUID.randomUUID().toString()).put("kind", "android_java").put("fatal", true)
                        .put("occurred_at", now()).put("screen", prefs.getString("screen", "unknown"))
                        .put("breadcrumbs", JSONArray(prefs.getString("breadcrumbs", "[]")))
                        .put("message", error.javaClass.name)
                    // Stack frames retain source locations; exception text may contain private input.
                    val trace = StringBuilder()
                    var cause: Throwable? = error
                    var depth = 0
                    while (cause != null && depth++ < 5) {
                        trace.append(cause.javaClass.name).append('\n')
                        cause.stackTrace.take(40).forEach { trace.append("\tat ").append(it.toString()).append('\n') }
                        cause = cause.cause
                    }
                    report.put("stack", trace.toString().take(10000))
                    synchronized(lock) {
                        val old = read(app); val next = JSONArray()
                        for (i in maxOf(0, old.length() - 19) until old.length()) next.put(old.get(i))
                        next.put(report); write(app, next)
                    }
                } catch (_: Throwable) { /* Never replace the original fatal error. */ }
                if (previous != null) previous.uncaughtException(thread, error)
                else android.os.Process.killProcess(android.os.Process.myPid())
            } finally { if (!alreadyRecording) recording.remove() }
        }
        installed = handler
        Thread.setDefaultUncaughtExceptionHandler(handler)
    }
    fun pending(context: Context): List<Map<String, Any?>> = synchronized(lock) {
        val rows = read(context)
        (0 until rows.length()).map { jsonMap(rows.getJSONObject(it)) }
    }
    fun acknowledge(context: Context, id: String) = synchronized(lock) {
        val rows = read(context); val next = JSONArray()
        for (i in 0 until rows.length()) if (rows.getJSONObject(i).optString("id") != id) next.put(rows.get(i))
        write(context, next)
    }
    private fun value(item: Any?): Any? = when (item) {
        is JSONObject -> jsonMap(item)
        is JSONArray -> (0 until item.length()).map { value(item.get(it)) }
        JSONObject.NULL -> null
        else -> item
    }
    private fun jsonMap(row: JSONObject): Map<String, Any?> = row.keys().asSequence().associateWith { value(row.get(it)) }
}
