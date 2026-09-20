package com.example.tiny_computer

import android.content.Context
import com.google.android.material.color.DynamicColors
import io.flutter.app.FlutterApplication
import me.weishu.reflection.Reflection

class MainApplication : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
        DynamicColors.applyToActivitiesIfAvailable(this@MainApplication)
    }

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        // TINY-OPT: unseal 失败不应该让整个 App 起不来（原来没有 try/catch，
        // 一旦 R8 把 FreeReflection 裁掉就是“每次启动必崩”）。
        try {
            Reflection.unseal(base)
        } catch (e: Throwable) {
            android.util.Log.w("TinyComputer", "Reflection.unseal failed: ${e.message}")
        }
    }

    companion object {
        // TINY-OPT: DocumentsProvider 是系统实例化的，拿不到 Application 引用，
        // 这里放一个静态 Context 供其做路径 containment 校验。
        //
        // ⚠️ @JvmStatic 是必需的：调用方是 Java（TinyDocumentsProvider.java）。
        // 没有它时，Kotlin 的 companion 成员在 Java 侧要写成
        // MainApplication.Companion.getAppContext()，直接 MainApplication.getAppContext()
        // 会报 "cannot find symbol"。
        @Volatile
        private var appContext: Context? = null

        @JvmStatic
        fun getAppContext(): Context {
            return appContext ?: throw IllegalStateException("Application is not created yet")
        }
    }
}