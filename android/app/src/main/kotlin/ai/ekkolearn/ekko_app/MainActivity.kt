package ai.ekkolearn.ekko_app

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai.ekkolearn.ekko_app/file_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") { result.notImplemented(); return@setMethodCallHandler }
                if (pending != null) { result.error("busy", "已有文件正在保存", null); return@setMethodCallHandler }
                try {
                    val file = File(call.argument<String>("path") ?: "").canonicalFile
                    val roots = listOf(cacheDir.canonicalPath, filesDir.canonicalPath)
                    require(file.isFile && roots.any { file.path.startsWith(it + File.separator) })
                    val name = (call.argument<String>("name") ?: "attachment").replace(Regex("[/\\\\\\x00-\\x1f]"), "_")
                    source = file
                    pending = result
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mime") ?: "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    startActivityForResult(intent, 8701)
                } catch (e: Exception) {
                    pending = null; source = null
                    result.error("export", "无法打开保存对话框", null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 8701) { super.onActivityResult(requestCode, resultCode, data); return }
        val callback = pending ?: return
        val file = source
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) {
            pending = null; source = null; callback.success(null); return
        }
        worker.execute {
            try {
                file.inputStream().use { input ->
                    val output = contentResolver.openOutputStream(uri, "w") ?: error("No destination")
                    output.use { input.copyTo(it, 64 * 1024) }
                }
                runOnUiThread { pending = null; source = null; callback.success(uri.toString()) }
            } catch (e: Exception) {
                // Best effort remove our incomplete newly created document.
                try { contentResolver.delete(uri, null, null) } catch (_: Exception) {}
                runOnUiThread { pending = null; source = null; callback.error("export", "保存失败，请检查存储空间", null) }
            }
        }
    }
}
