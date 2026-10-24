package app.swiftdrop

import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var networkPermissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.swiftdrop/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestLocalNetwork" -> {
                        // String literal allows compiling with SDK 36 while requesting
                        // the runtime permission on OS versions that enforce it.
                        val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                        if (Build.VERSION.SDK_INT < 37 || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else if (networkPermissionResult != null) {
                            result.error("BUSY", "A permission request is pending", null)
                        } else {
                            networkPermissionResult = result
                            requestPermissions(arrayOf(permission), 4901)
                        }
                    }
                    "exportBatch" -> {
                        val path = call.argument<String>("path")
                        if (path == null) { result.error("PATH", "Missing batch path", null) }
                        else worker.execute {
                            try {
                                val source = File(path).canonicalFile
                                // Only app-owned verified files may be exported, never
                                // arbitrary paths supplied through the platform channel.
                                val allowed = File(applicationInfo.dataDir).canonicalFile
                                require(source.path.startsWith(allowed.path + File.separator)) { "Not app-owned" }
                                require(source.name == "files" && source.isDirectory) { "Invalid batch" }
                                var count = 0
                                source.walkTopDown().filter { it.isFile }.forEach { file ->
                                    val canonical = file.canonicalFile
                                    require(canonical.path.startsWith(source.path + File.separator)) { "Unsafe source" }
                                    val relative = file.relativeTo(source).invariantSeparatorsPath
                                    val parent = relative.substringBeforeLast('/', "")
                                    val values = ContentValues().apply {
                                        put(MediaStore.Downloads.DISPLAY_NAME, file.name)
                                        put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                                        put(MediaStore.Downloads.RELATIVE_PATH,
                                            Environment.DIRECTORY_DOWNLOADS + "/SwiftDrop/" + source.parentFile!!.name + "/" + parent)
                                        put(MediaStore.Downloads.IS_PENDING, 1)
                                    }
                                    val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                        ?: error("Cannot create Downloads entry")
                                    try {
                                        contentResolver.openOutputStream(uri, "w").use { output ->
                                            requireNotNull(output) { "Destination is not writable" }
                                            file.inputStream().use { input -> input.copyTo(output, 64 * 1024) }
                                        }
                                        val ready = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
                                        contentResolver.update(uri, ready, null, null)
                                        count++
                                    } catch (error: Exception) {
                                        contentResolver.delete(uri, null, null)
                                        throw error
                                    }
                                }
                                runOnUiThread { result.success(count) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("EXPORT", "Export failed: check free space and storage access", null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4901) {
            networkPermissionResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            networkPermissionResult = null
        }
    }
    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}
