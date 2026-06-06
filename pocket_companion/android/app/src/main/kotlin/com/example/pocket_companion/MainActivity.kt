package com.example.pocket_companion

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pocket_companion/device_capabilities"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "speechRecognitionStatus" -> result.success(speechRecognitionStatus())
                "recordAudioClip" -> {
                    val durationMs = (call.argument<Int>("durationMs") ?: 5000).coerceIn(1000, 12000)
                    recordAudioClip(durationMs, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun speechRecognitionStatus(): Map<String, Any> {
        val service = Settings.Secure.getString(
            contentResolver,
            "voice_recognition_service"
        ).orEmpty()
        val blocked = service.contains("FakeRecognitionService", ignoreCase = true) ||
            service.contains("com.huawei.vassistant", ignoreCase = true)
        return mapOf(
            "available" to !blocked,
            "service" to service,
            "reason" to if (blocked) "blocked_huawei_fake_recognition_service" else ""
        )
    }

    private fun recordAudioClip(durationMs: Int, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("record_audio_denied", "Microphone permission is not granted.", null)
            return
        }
        val outputFile = File.createTempFile("mengmeng_voice_", ".m4a", cacheDir)
        val recorder = MediaRecorder()
        try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(16000)
            recorder.setAudioChannels(1)
            recorder.setAudioEncodingBitRate(64000)
            recorder.setOutputFile(outputFile.absolutePath)
            recorder.prepare()
            recorder.start()
        } catch (error: Exception) {
            try {
                recorder.release()
            } catch (_: Exception) {}
            result.error("record_audio_start_failed", error.message, null)
            return
        }

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                recorder.stop()
                recorder.release()
                result.success(outputFile.absolutePath)
            } catch (error: Exception) {
                try {
                    recorder.release()
                } catch (_: Exception) {}
                result.error("record_audio_stop_failed", error.message, null)
            }
        }, durationMs.toLong())
    }
}
