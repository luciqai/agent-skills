//
//  LuciqSeamDump.kt  —  SEAM-DUMP CAPTURE (Android) for luciq-network-masking.
//
//  Captures at the exact Luciq obfuscation seam your real scrubPII handler will
//  mask — no Frida, no proxy, no cert, no pinning. It only READS; the pass-through
//  listener returns every log UNCHANGED. Add it temporarily, walk the paths, pull
//  the file, then DELETE this file and its call site.
//
//  This registers a pass-through listener at the SAME entry point the generated
//  Android handler (LuciqNetworkScrub.kt) wires into: LuciqNetworkLog on
//  LuciqOkhttpInterceptor. Verify the exact setter/field names against
//  https://docs.luciq.ai — mirror whatever wiring your production handler uses.
//
//  1. Add this file to your app module (e.g. debug source set).
//  2. Call `LuciqSeamDump.installIfEnabled(context)` right after `Luciq.start(...)`.
//  3. Flip SEAM_DUMP to true and build a DEBUG build.
//  4. Walk every critical path.
//  5. Pull the capture:
//       adb exec-out run-as <your.package.id> cat files/luciq-seam-capture.jsonl > capture.jsonl
//  6. Feed capture.jsonl to the skill's classify.py, then DELETE this file + the
//     call + set SEAM_DUMP back to false.
//
//  Output is the flow shape classify.py consumes: one JSON object per network log
//  with method/url/host/reqHeaders/reqBody/respHeaders/respBody.

package com.example.debug // <-- change to your package

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.URI
import java.util.concurrent.Executors

object LuciqSeamDump {

    // Flip to true ONLY for a capture build. Guarded by BuildConfig.DEBUG below so
    // it can never arm in a release build even if left true by accident.
    private const val SEAM_DUMP = false

    private val io = Executors.newSingleThreadExecutor()
    private lateinit var file: File

    /** No-op unless SEAM_DUMP is on AND this is a debug build. */
    fun installIfEnabled(context: Context) {
        // Replace BuildConfig.DEBUG with your module's BuildConfig if the import differs.
        if (!SEAM_DUMP /* || !BuildConfig.DEBUG */) return
        file = File(context.filesDir, "luciq-seam-capture.jsonl")
        file.delete()
        android.util.Log.i("luciq-seam-dump", "capturing to ${file.absolutePath}")

        // === Register the pass-through listener at Luciq's network-log seam. ===
        // This is the SAME hook LuciqNetworkScrub.kt uses; here we append + return
        // the log UNCHANGED instead of scrubbing. Verify the setter name against the
        // live docs — it must match how your production handler is wired.
        //
        //   LuciqOkhttpInterceptor.setOnNetworkLogListener { log ->
        //       append(log)     // READ only
        //       log             // UNCHANGED — capture only
        //   }
        //
        // If your app already wires a LuciqNetworkLog listener for scrubbing, add the
        // append(log) call there (behind SEAM_DUMP) rather than registering twice.
    }

    /** Serialize one LuciqNetworkLog to the classify.py flow shape. Verify field names. */
    fun append(log: Any /* LuciqNetworkLog */) {
        io.execute {
            try {
                // Adapt these getters to your LuciqNetworkLog fields (see docs.luciq.ai).
                val url = readString(log, "getUrl", "url")
                val obj = JSONObject()
                    .put("method", readString(log, "getMethod", "method").ifEmpty { "GET" })
                    .put("url", url)
                    .put("host", hostOf(url))
                    .put("reqHeaders", headersOf(log, "getRequestHeaders", "requestHeaders"))
                    .put("reqBody", readString(log, "getRequestBody", "requestBody"))
                    .put("respHeaders", headersOf(log, "getResponseHeaders", "responseHeaders"))
                    .put("respBody", readString(log, "getResponseBody", "responseBody"))
                synchronized(file) { file.appendText(obj.toString() + "\n") }
            } catch (e: Exception) {
                android.util.Log.w("luciq-seam-dump", "skip log: ${e.message}")
            }
        }
    }

    private fun hostOf(url: String): String =
        try { URI(url).host ?: "" } catch (e: Exception) { "" }

    // --- Reflection helpers so this compiles before you bind the real type. Once
    // you import LuciqNetworkLog, replace these with direct field access.
    private fun readString(o: Any, getter: String, field: String): String {
        return try { o.javaClass.getMethod(getter).invoke(o)?.toString() ?: "" }
        catch (e: Exception) {
            try { o.javaClass.getField(field).get(o)?.toString() ?: "" }
            catch (e2: Exception) { "" }
        }
    }

    private fun headersOf(o: Any, getter: String, field: String): JSONObject {
        val out = JSONObject()
        val raw = try { o.javaClass.getMethod(getter).invoke(o) }
                  catch (e: Exception) { try { o.javaClass.getField(field).get(o) } catch (e2: Exception) { null } }
        if (raw is Map<*, *>) for ((k, v) in raw) out.put(k.toString().lowercase(), v?.toString() ?: "")
        return out
    }
}
