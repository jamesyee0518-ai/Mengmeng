package com.example.pocket_companion

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val recordingInProgress = AtomicBoolean(false)
    private var activeRecordingCancel: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pocket_companion/device_capabilities"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "speechRecognitionStatus" -> result.success(speechRecognitionStatus())
                "microphonePermissionStatus" -> result.success(microphonePermissionStatus())
                "cancelRecording" -> result.success(cancelActiveRecording())
                "recordAudioClip" -> {
                    val durationMs = (call.argument<Int>("durationMs") ?: 5000).coerceIn(1000, 12000)
                    recordAudioClip(durationMs, result)
                }
                "recordUntilSilence" -> {
                    val maxDurationMs = (call.argument<Int>("maxDurationMs") ?: 12000).coerceIn(1000, 30000)
                    val silenceTimeoutMs = (call.argument<Int>("silenceTimeoutMs") ?: 1200).coerceIn(300, 5000)
                    val minSpeechMs = (call.argument<Int>("minSpeechMs") ?: 400).coerceIn(100, 5000)
                    val startTimeoutMs = (call.argument<Int>("startTimeoutMs") ?: 3000).coerceIn(500, 10000)
                    recordUntilSilence(maxDurationMs, silenceTimeoutMs, minSpeechMs, startTimeoutMs, result)
                }
                "detectBargeIn" -> {
                    val maxDurationMs = (call.argument<Int>("maxDurationMs") ?: 10000).coerceIn(500, 30000)
                    val minSpeechMs = (call.argument<Int>("minSpeechMs") ?: 400).coerceIn(100, 5000)
                    val minAvgRms = (call.argument<Double>("minAvgRms") ?: 180.0).coerceIn(0.0, 10000.0)
                    val minMaxRms = (call.argument<Double>("minMaxRms") ?: 1200.0).coerceIn(0.0, 30000.0)
                    val minSpeechLikeRatio = (call.argument<Double>("minSpeechLikeRatio") ?: 0.18).coerceIn(0.0, 1.0)
                    detectBargeIn(maxDurationMs, minSpeechMs, minAvgRms, minMaxRms, minSpeechLikeRatio, result)
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

    private fun microphonePermissionStatus(): Map<String, Any> {
        val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        return mapOf(
            "status" to if (granted) "granted" else "denied"
        )
    }

    private fun recordAudioClip(durationMs: Int, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("record_audio_denied", "Microphone permission is not granted.", null)
            return
        }
        if (!recordingInProgress.compareAndSet(false, true)) {
            result.success(audioClipBusyResult())
            return
        }
        val outputFile = File.createTempFile("mengmeng_voice_", ".m4a", cacheDir)
        val recorder = MediaRecorder()
        val audioStats = AudioStats()
        val statsRunning = AtomicBoolean(false)
        val finished = AtomicBoolean(false)
        var statsThread: Thread? = null
        val startedAt = SystemClock.elapsedRealtime()
        val mainHandler = Handler(Looper.getMainLooper())

        fun finish(reason: String) {
            if (!finished.compareAndSet(false, true)) {
                return
            }
            mainHandler.post {
                try {
                    recorder.stop()
                } catch (_: Exception) {}
                try {
                    recorder.release()
                } catch (_: Exception) {}
                statsRunning.set(false)
                try {
                    statsThread?.join(250)
                } catch (_: Exception) {}
                val actualDurationMs = (SystemClock.elapsedRealtime() - startedAt).toInt()
                val snapshot = audioStats.snapshot(actualDurationMs, minSpeechMs = 0)
                result.success(
                    mapOf(
                        "path" to outputFile.absolutePath,
                        "durationMs" to actualDurationMs,
                        "speechDurationMs" to snapshot.speechDurationMs,
                        "avgRms" to snapshot.avgRms,
                        "maxRms" to snapshot.maxRms,
                        "speechLikeRatio" to snapshot.speechLikeRatio,
                        "hasSpeechLikeAudio" to snapshot.hasSpeechLikeAudio,
                        "reason" to if (snapshot.statsAvailable) reason else "audio_stats_unavailable"
                    )
                )
                clearActiveRecordingCancel()
                recordingInProgress.set(false)
            }
        }

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
            statsRunning.set(true)
            statsThread = startAudioStatsThread(statsRunning, audioStats)
            setActiveRecordingCancel { finish("cancelled") }
        } catch (error: Exception) {
            recordingInProgress.set(false)
            clearActiveRecordingCancel()
            try {
                recorder.release()
            } catch (_: Exception) {}
            result.error("record_audio_start_failed", error.message, null)
            return
        }

        mainHandler.postDelayed({ finish("max_duration") }, durationMs.toLong())
    }

    private fun recordUntilSilence(
        maxDurationMs: Int,
        silenceTimeoutMs: Int,
        minSpeechMs: Int,
        startTimeoutMs: Int,
        result: MethodChannel.Result
    ) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("record_audio_denied", "Microphone permission is not granted.", null)
            return
        }
        if (!recordingInProgress.compareAndSet(false, true)) {
            result.success(audioClipBusyResult())
            return
        }
        val outputFile = File.createTempFile("mengmeng_voice_", ".m4a", cacheDir)
        val recorder = MediaRecorder()
        val audioStats = AudioStats()
        val statsRunning = AtomicBoolean(false)
        val finished = AtomicBoolean(false)
        var statsThread: Thread? = null
        val startedAt = SystemClock.elapsedRealtime()
        val mainHandler = Handler(Looper.getMainLooper())

        fun finish(reason: String) {
            if (!finished.compareAndSet(false, true)) {
                return
            }
            mainHandler.post {
                try {
                    recorder.stop()
                } catch (_: Exception) {}
                try {
                    recorder.release()
                } catch (_: Exception) {}
                statsRunning.set(false)
                try {
                    statsThread?.join(250)
                } catch (_: Exception) {}
                val actualDurationMs = (SystemClock.elapsedRealtime() - startedAt).toInt()
                val snapshot = audioStats.snapshot(actualDurationMs, minSpeechMs)
                val effectiveReason = when {
                    !snapshot.statsAvailable -> "audio_stats_unavailable"
                    reason == "silence_timeout" && snapshot.speechDurationMs < minSpeechMs -> "too_short_speech"
                    else -> reason
                }
                val hasSpeechLikeAudio = snapshot.hasSpeechLikeAudio &&
                    effectiveReason != "start_timeout" &&
                    effectiveReason != "too_short_speech"
                result.success(
                    mapOf(
                        "path" to outputFile.absolutePath,
                        "durationMs" to actualDurationMs,
                        "speechDurationMs" to snapshot.speechDurationMs,
                        "avgRms" to snapshot.avgRms,
                        "maxRms" to snapshot.maxRms,
                        "speechLikeRatio" to snapshot.speechLikeRatio,
                        "hasSpeechLikeAudio" to hasSpeechLikeAudio,
                        "reason" to effectiveReason
                    )
                )
                clearActiveRecordingCancel()
                recordingInProgress.set(false)
            }
        }

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
            statsRunning.set(true)
            statsThread = startAudioStatsThread(statsRunning, audioStats)
            setActiveRecordingCancel { finish("cancelled") }
        } catch (error: Exception) {
            recordingInProgress.set(false)
            clearActiveRecordingCancel()
            try {
                recorder.release()
            } catch (_: Exception) {}
            result.error("record_audio_start_failed", error.message, null)
            return
        }

        Thread {
            var speechStarted = false
            while (!finished.get()) {
                val elapsedMs = (SystemClock.elapsedRealtime() - startedAt).toInt()
                val snapshot = audioStats.snapshot(elapsedMs, minSpeechMs)
                if (elapsedMs >= maxDurationMs) {
                    finish(if (snapshot.statsAvailable) "max_duration" else "audio_stats_unavailable")
                    return@Thread
                }
                if (!snapshot.statsAvailable) {
                    SystemClock.sleep(80)
                    continue
                }
                if (!speechStarted && snapshot.speechStarted) {
                    speechStarted = true
                }
                if (!speechStarted && elapsedMs >= startTimeoutMs) {
                    finish("start_timeout")
                    return@Thread
                }
                if (speechStarted &&
                    snapshot.silenceDurationMs >= silenceTimeoutMs
                ) {
                    finish("silence_timeout")
                    return@Thread
                }
                SystemClock.sleep(80)
            }
        }.start()
    }

    private fun detectBargeIn(
        maxDurationMs: Int,
        minSpeechMs: Int,
        minAvgRms: Double,
        minMaxRms: Double,
        minSpeechLikeRatio: Double,
        result: MethodChannel.Result
    ) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("record_audio_denied", "Microphone permission is not granted.", null)
            return
        }
        if (!recordingInProgress.compareAndSet(false, true)) {
            result.success(bargeInBusyResult())
            return
        }
        val audioStats = AudioStats()
        val statsRunning = AtomicBoolean(true)
        val finished = AtomicBoolean(false)
        val startedAt = SystemClock.elapsedRealtime()
        val mainHandler = Handler(Looper.getMainLooper())
        val statsThread = startAudioStatsThread(statsRunning, audioStats)

        fun finish(detected: Boolean, reason: String) {
            if (!finished.compareAndSet(false, true)) {
                return
            }
            statsRunning.set(false)
            try {
                statsThread.join(250)
            } catch (_: Exception) {}
            val actualDurationMs = (SystemClock.elapsedRealtime() - startedAt).toInt()
            val snapshot = audioStats.snapshot(actualDurationMs, minSpeechMs)
            val effectiveReason = when {
                !snapshot.statsAvailable -> "audio_stats_unavailable"
                detected -> "barge_in_detected"
                reason != "max_duration" -> reason
                snapshot.speechDurationMs > 0 && snapshot.speechDurationMs < minSpeechMs -> "too_short_speech"
                snapshot.avgRms > 0.0 || snapshot.maxRms > 0.0 || snapshot.speechLikeRatio > 0.0 -> "low_rms"
                else -> "max_duration"
            }
            mainHandler.post {
                result.success(
                    mapOf(
                        "detected" to detected,
                        "durationMs" to actualDurationMs,
                        "speechDurationMs" to snapshot.speechDurationMs,
                        "avgRms" to snapshot.avgRms,
                        "maxRms" to snapshot.maxRms,
                        "speechLikeRatio" to snapshot.speechLikeRatio,
                        "reason" to effectiveReason
                    )
                )
                clearActiveRecordingCancel()
                recordingInProgress.set(false)
            }
        }

        setActiveRecordingCancel { finish(false, "cancelled") }

        Thread {
            while (!finished.get()) {
                val elapsedMs = (SystemClock.elapsedRealtime() - startedAt).toInt()
                val snapshot = audioStats.snapshot(elapsedMs, minSpeechMs)
                if (snapshot.statsAvailable &&
                    snapshot.speechDurationMs >= minSpeechMs &&
                    snapshot.avgRms >= minAvgRms &&
                    snapshot.maxRms >= minMaxRms &&
                    snapshot.speechLikeRatio >= minSpeechLikeRatio
                ) {
                    finish(true, "barge_in_detected")
                    return@Thread
                }
                if (elapsedMs >= maxDurationMs) {
                    finish(false, if (snapshot.statsAvailable) "max_duration" else "audio_stats_unavailable")
                    return@Thread
                }
                SystemClock.sleep(80)
            }
        }.start()
    }

    private fun audioClipBusyResult(): Map<String, Any> {
        return mapOf(
            "path" to "",
            "durationMs" to 0,
            "speechDurationMs" to 0,
            "avgRms" to 0.0,
            "maxRms" to 0.0,
            "speechLikeRatio" to 0.0,
            "hasSpeechLikeAudio" to false,
            "reason" to "recording_in_progress"
        )
    }

    private fun bargeInBusyResult(): Map<String, Any> {
        return mapOf(
            "detected" to false,
            "durationMs" to 0,
            "speechDurationMs" to 0,
            "avgRms" to 0.0,
            "maxRms" to 0.0,
            "speechLikeRatio" to 0.0,
            "reason" to "recording_in_progress"
        )
    }

    @Synchronized
    private fun setActiveRecordingCancel(cancel: () -> Unit) {
        activeRecordingCancel = cancel
    }

    @Synchronized
    private fun clearActiveRecordingCancel() {
        activeRecordingCancel = null
    }

    @Synchronized
    private fun cancelActiveRecording(): Boolean {
        val cancel = activeRecordingCancel ?: return false
        cancel()
        return true
    }

    private fun startAudioStatsThread(
        running: AtomicBoolean,
        stats: AudioStats
    ): Thread {
        val thread = Thread {
            val sampleRate = 16000
            val minBuffer = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBuffer <= 0) {
                running.set(false)
                return@Thread
            }
            val bufferSize = maxOf(minBuffer, sampleRate / 5)
            val buffer = ShortArray(bufferSize)
            val audioRecord = try {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize * 2
                )
            } catch (_: Exception) {
                running.set(false)
                return@Thread
            }
            try {
                if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
                    return@Thread
                }
                audioRecord.startRecording()
                while (running.get()) {
                    val read = audioRecord.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        stats.addFrame(calculateRms(buffer, read))
                    }
                }
            } catch (_: Exception) {
                // RMS is a quality hint only; recording itself continues through MediaRecorder.
            } finally {
                try {
                    audioRecord.stop()
                } catch (_: Exception) {}
                audioRecord.release()
            }
        }
        thread.name = "MengmengAudioStats"
        thread.start()
        return thread
    }

    private fun calculateRms(buffer: ShortArray, read: Int): Double {
        if (read <= 0) return 0.0
        var sum = 0.0
        for (i in 0 until read) {
            sum += buffer[i] * buffer[i]
        }
        return Math.sqrt(sum / read)
    }

    private class AudioStats {
        private val speechRmsThreshold = 350.0
        private var frameCount = 0
        private var speechLikeFrames = 0
        private var rmsSum = 0.0
        private var maxRms = 0.0
        private var firstSpeechAtMs = 0L
        private var lastSpeechAtMs = 0L

        @Synchronized
        fun addFrame(rms: Double) {
            val now = SystemClock.elapsedRealtime()
            frameCount += 1
            rmsSum += rms
            if (rms > maxRms) {
                maxRms = rms
            }
            if (rms >= speechRmsThreshold) {
                speechLikeFrames += 1
                if (firstSpeechAtMs == 0L) {
                    firstSpeechAtMs = now
                }
                lastSpeechAtMs = now
            }
        }

        @Synchronized
        fun snapshot(durationMs: Int, minSpeechMs: Int): AudioStatsSnapshot {
            val avgRms = if (frameCount > 0) rmsSum / frameCount else 0.0
            val speechLikeRatio = if (frameCount > 0) {
                speechLikeFrames.toDouble() / frameCount.toDouble()
            } else {
                0.0
            }
            val now = SystemClock.elapsedRealtime()
            val speechDurationMs = if (firstSpeechAtMs > 0L && lastSpeechAtMs >= firstSpeechAtMs) {
                (lastSpeechAtMs - firstSpeechAtMs + 80L).toInt()
            } else {
                0
            }
            val silenceDurationMs = if (lastSpeechAtMs > 0L) {
                (now - lastSpeechAtMs).toInt()
            } else {
                durationMs
            }
            val hasSpeechLikeAudio = frameCount == 0 || durationMs >= 600 &&
                avgRms >= 80.0 &&
                maxRms >= 400.0 &&
                speechLikeRatio >= 0.08 &&
                speechDurationMs >= minSpeechMs
            return AudioStatsSnapshot(
                speechStarted = firstSpeechAtMs > 0L,
                speechDurationMs = speechDurationMs,
                silenceDurationMs = silenceDurationMs,
                avgRms = avgRms,
                maxRms = maxRms,
                speechLikeRatio = speechLikeRatio,
                hasSpeechLikeAudio = hasSpeechLikeAudio,
                statsAvailable = frameCount > 0
            )
        }
    }

    private data class AudioStatsSnapshot(
        val speechStarted: Boolean,
        val speechDurationMs: Int,
        val silenceDurationMs: Int,
        val avgRms: Double,
        val maxRms: Double,
        val speechLikeRatio: Double,
        val hasSpeechLikeAudio: Boolean,
        val statsAvailable: Boolean
    )
}
