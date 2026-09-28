package com.example.pocket_companion

import android.content.Context
import io.flutter.app.FlutterApplication

/**
 * DJI Mobile SDK V4 采用加固分发：真实类加密在 libdataclx.so 中，
 * 必须在 Application.attachBaseContext 阶段调用 cySdkyc Helper.install
 * 解密注入，任何 dji.* 类才能被加载（官方 Sample 同款用法）。
 */
class CompanionApplication : FlutterApplication() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        try {
            com.cySdkyc.clx.Helper.install(this)
        } catch (error: Throwable) {
            android.util.Log.e("DjiGimbal", "Helper.install failed", error)
        }
    }
}
