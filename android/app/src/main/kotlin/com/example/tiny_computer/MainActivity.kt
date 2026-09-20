package com.example.tiny_computer

import android.system.Os.setenv

import android.content.Intent
import androidx.annotation.NonNull
import androidx.annotation.Keep
import androidx.appcompat.app.AppCompatDelegate
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "android").setMethodCallHandler {
            // 注册通道并设置方法调用处理器
            call, result ->
            // 判断方法名
            when (call.method) {
                "launchSignal9Page" -> {
                    startActivity(Intent(this, Signal9Activity::class.java))
                    result.success(0)
                }
                "getNativeLibraryPath" -> {
                    result.success(getApplicationInfo().nativeLibraryDir)
                }
                // TINY-OPT: 首启空间预检用。返回应用私有目录所在分区的可用字节数，
                // Dart 侧据此在“复制容器系统”之前给出可读的错误提示，而不是写到一半失败。
                "getUsableSpace" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "path is required", null)
                    } else {
                        try {
                            result.success(java.io.File(path).usableSpace)
                        } catch (e: Throwable) {
                            result.error("SPACE_QUERY_FAILED", e.message, null)
                        }
                    }
                }
                "startStreaming" -> {
                    AudioStream.startStreaming(call.argument("path")!!)
                }
                "stopStreaming" -> {
                    AudioStream.stopStreaming()
                }
                else -> {
                    // 不支持的方法名
                    result.notImplemented()
                }
            }
        }
    }

}
