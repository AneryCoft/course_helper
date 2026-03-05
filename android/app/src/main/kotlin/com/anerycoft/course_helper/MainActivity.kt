package com.anerycoft.coursehelper

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 同意百度定位 SDK 隐私政策
        try {
            val locationClientClass = Class.forName("com.baidu.location.LocationClient")
            val setAgreePrivacyMethod = locationClientClass.getMethod("setAgreePrivacy", Boolean::class.javaPrimitiveType)
            setAgreePrivacyMethod.invoke(null, true)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
}