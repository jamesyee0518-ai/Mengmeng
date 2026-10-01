package com.example.pocket_companion

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.os.Handler
import android.os.Looper
import dji.common.error.DJIError
import dji.common.error.DJISDKError
import dji.common.gimbal.GimbalState
import dji.common.gimbal.Rotation
import dji.common.gimbal.RotationMode
import dji.common.util.CommonCallbacks
import dji.sdk.base.BaseComponent
import dji.sdk.base.BaseProduct
import dji.sdk.products.HandHeld
import dji.sdk.sdkmanager.BluetoothProductConnector
import dji.sdk.sdkmanager.DJISDKInitEvent
import dji.sdk.sdkmanager.DJISDKManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * DJI Mobile SDK V4 桥接层：注册应用、通过蓝牙连接手持云台（Osmo Mobile 系列），
 * 并把 Flutter 侧的云台控制指令转发给 SDK。
 *
 * 所有 SDK 回调先切回主线程再写入 Flutter 通道。
 * API 用法与官方 Sample（Mobile-SDK-Android-V4 4.18）保持一致：
 * - 速度控制: gimbal.rotate(Rotation(mode=SPEED, pitch=°/s, yaw=°/s, time=0))
 * - 停止转动: gimbal.rotate(null)
 * - 姿态推送: gimbal.setStateCallback(GimbalState.Callback)
 */
class DjiGimbalPlugin {

    companion object {
        private const val METHOD_CHANNEL = "pocket_companion/dji_gimbal"
        private const val EVENT_CHANNEL = "pocket_companion/dji_gimbal_state"
        private const val PERMISSION_REQUEST_CODE = 7001
        private const val TAG = "DjiGimbal"
        private const val ATTITUDE_PUSH_MIN_INTERVAL_MS = 100L
        private const val BLUETOOTH_SEARCH_TIMEOUT_MS = 20_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val registered = HashSet<String>()
    @Volatile private var phase: String = "idle"
    @Volatile private var productName: String = ""
    @Volatile private var gimbal: dji.sdk.gimbal.Gimbal? = null
    @Volatile private var lastAttitudePushAt = 0L
    private val bluetoothConnecting = HashSet<String>()
    @Volatile private var searchGeneration = 0

    fun attach(activity: Activity, flutterEngine: FlutterEngine) {
        Log.e(TAG, "attach: wiring channels")
        detach()
        mainHandler.postDelayed({ autoConnect() }, 1500)
        scheduleReconnectAttempts()
        this.activity = activity
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(statusPayload())
                    "register" -> handleRegister(result)
                    "connectBluetooth" -> handleConnectBluetooth(result)
                    "setVelocity" -> handleSetVelocity(call, result)
                    "stop" -> handleStop(result)
                    "rotateTo" -> handleRotateTo(call, result)
                    "center" -> handleCenter(result)
                    else -> result.notImplemented()
                }
            }
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    pushEvent(phasePayload())
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    fun detach() {
        searchGeneration += 1
        mainHandler.removeCallbacksAndMessages(null)
        bluetoothConnecting.clear()
        try {
            gimbal?.setStateCallback(null)
        } catch (_: Exception) {
        }
        gimbal = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        activity = null
        eventSink = null
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            // 用户授权后由 Flutter 侧重试 register。
        }
    }

    // ------------------------------------------------------------------ 自动重连

    /// App 启动即自动注册并尝试重连上次的云台；未连上则主动蓝牙搜索。
    private fun autoConnect() {
        val activity = activity ?: return
        if (missingBluetoothPermissions().isNotEmpty()) {
            Log.e(TAG, "autoConnect: missing permissions, wait for manual trigger")
            return
        }
        if (!registered.contains(APP_REGISTER_KEY)) {
            Log.e(TAG, "autoConnect: registerApp")
            try {
                DJISDKManager.getInstance().registerApp(
                    activity.applicationContext,
                    sdkManagerCallback,
                )
                registered.add(APP_REGISTER_KEY)
            } catch (error: Exception) {
                registered.remove(APP_REGISTER_KEY)
                Log.e(TAG, "autoConnect: register failed ${error.message}")
                return
            }
        }
    }

    private var reconnectAttempts = 0

    /// 云台未连接期间每 10s 重试（OM3 休眠唤醒后可自动接回），共约 2 分钟。
    private fun scheduleReconnectAttempts() {
        mainHandler.postDelayed({
            if (gimbal != null || !registered.contains(APP_REGISTER_KEY)) {
                return@postDelayed
            }
            reconnectAttempts += 1
            if (reconnectAttempts > 36) {
                Log.e(TAG, "reconnect attempts exhausted")
                return@postDelayed
            }
            Log.e(TAG, "reconnect attempt #$reconnectAttempts")
            try {
                DJISDKManager.getInstance().startConnectionToProduct()
            } catch (_: Exception) {
            }
            if (bluetoothConnecting.isEmpty()) {
                startBluetoothSearch()
            }
            scheduleReconnectAttempts()
        }, 10_000)
    }

    // ------------------------------------------------------------------ 注册

    private fun handleRegister(result: MethodChannel.Result) {
        val missing = missingBluetoothPermissions()
        if (missing.isNotEmpty()) {
            activity?.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
            result.error("bluetooth_permission_needed", "蓝牙权限未授予，授权后请重试", null)
            return
        }
        if (registered.contains(APP_REGISTER_KEY)) {
            result.success(statusPayload())
            return
        }
        setPhase("registering")
        Log.e(TAG, "registerApp: begin")
        try {
            DJISDKManager.getInstance().registerApp(
                activity?.applicationContext,
                sdkManagerCallback,
            )
            registered.add(APP_REGISTER_KEY)
            result.success(statusPayload())
        } catch (error: Exception) {
            registered.remove(APP_REGISTER_KEY)
            setPhase("error")
            pushEvent(mapOf("type" to "error", "message" to "register failed: ${error.message}"))
            result.error("register_failed", error.message, null)
        }
    }

    private val sdkManagerCallback = object : DJISDKManager.SDKManagerCallback {
        override fun onRegister(djiError: DJIError?) {
            Log.e(TAG, "onRegister: ${djiError?.description}")
            if (djiError == DJISDKError.REGISTRATION_SUCCESS) {
                setPhase("registered")
                try {
                    DJISDKManager.getInstance().startConnectionToProduct()
                } catch (_: Exception) {
                }
            } else {
                setPhase("error")
                pushEvent(
                    mapOf(
                        "type" to "error",
                        "message" to "register failed: ${djiError?.description ?: "unknown"}",
                    )
                )
            }
        }

        override fun onProductDisconnect() {
            mainHandler.post {
                gimbal = null
                productName = ""
                setPhase("disconnected")
            }
        }

        override fun onProductConnect(baseProduct: BaseProduct?) {
            mainHandler.post { bindProduct(baseProduct) }
        }

        override fun onProductChanged(baseProduct: BaseProduct?) {
            mainHandler.post {
                if (baseProduct != null) {
                    bindProduct(baseProduct)
                }
            }
        }

        override fun onComponentChange(
            componentKey: BaseProduct.ComponentKey?,
            oldComponent: BaseComponent?,
            newComponent: BaseComponent?,
        ) {
        }

        override fun onInitProcess(djisdkInitEvent: DJISDKInitEvent?, totalProcessInPercent: Int) {
            Log.e(TAG, "init process: $djisdkInitEvent $totalProcessInPercent%")
            if (djisdkInitEvent?.initializationState ==
                DJISDKInitEvent.InitializationState.DATABASE_LOADED
            ) {
                mainHandler.postDelayed({
                    if (gimbal == null && bluetoothConnecting.isEmpty()) {
                        Log.e(TAG, "init complete, start bluetooth search")
                        startBluetoothSearch()
                    }
                }, 1000)
            }
        }

        override fun onDatabaseDownloadProgress(current: Long, total: Long) {
        }
    }

    // ------------------------------------------------------------------ 蓝牙连接

    private fun handleConnectBluetooth(result: MethodChannel.Result) {
        val missing = missingBluetoothPermissions()
        if (missing.isNotEmpty()) {
            activity?.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
            result.error("bluetooth_permission_needed", "蓝牙权限未授予，授权后请重试", null)
            return
        }
        if (!registered.contains(APP_REGISTER_KEY)) {
            result.error("not_registered", "请先调用 register", null)
            return
        }
        if (!startBluetoothSearch()) {
            result.error("connector_unavailable", "蓝牙连接器不可用", null)
            return
        }
        result.success(statusPayload())
    }

    private var searchRetryCount = 0

    /// 返回 false 表示蓝牙连接器不可用。
    private fun startBluetoothSearch(): Boolean {
        if (activity == null) return false
        if (gimbal != null) return true
        val connector: BluetoothProductConnector =
            DJISDKManager.getInstance().bluetoothProductConnector ?: return false
        if (!bluetoothConnecting.add(BLE_CONNECT_KEY)) {
            return true
        }
        val generation = ++searchGeneration
        Log.e(TAG, "searchBluetoothProducts: begin")
        setPhase("connecting")
        val listCallback = object : BluetoothProductConnector.BluetoothDevicesListCallback {
            override fun onUpdate(devices: MutableList<dji.sdk.sdkmanager.BluetoothDevice>) {
                Log.e(TAG, "ble list onUpdate: count=${devices.size} names=${devices.mapNotNull { it.name }}")
                if (generation != searchGeneration || gimbal != null ||
                    devices.isEmpty() || !bluetoothConnecting.contains(BLE_CONNECT_KEY)) {
                    return
                }
                val target = devices.firstOrNull { device ->
                    device.name?.contains("osmo", ignoreCase = true) == true
                } ?: devices.firstOrNull() ?: return
                if (!bluetoothConnecting.remove(BLE_CONNECT_KEY)) {
                    return
                }
                connector.setBluetoothDevicesListCallback(null)
                connector.connect(
                    target,
                    object : CommonCallbacks.CompletionCallback<DJIError> {
                        override fun onResult(error: DJIError?) {
                            Log.e(TAG, "connect onResult: ${error?.description ?: "success"}")
                            if (generation != searchGeneration || gimbal != null) return
                            if (error != null) {
                                setPhase("error")
                                pushEvent(
                                    mapOf(
                                        "type" to "error",
                                        "message" to "bluetooth connect failed: ${error.description}",
                                    )
                                )
                            }
                            // 连接成功由 onProductConnect 统一推进 phase。
                        }
                    },
                )
            }
        }
        connector.setBluetoothDevicesListCallback(listCallback)
        connector.searchBluetoothProducts(
            object : CommonCallbacks.CompletionCallback<DJIError> {
                override fun onResult(error: DJIError?) {
                    if (generation != searchGeneration || gimbal != null) return
                    Log.e(TAG, "search onResult: ${error?.description ?: "success"}")
                    if (error != null) {
                        bluetoothConnecting.remove(BLE_CONNECT_KEY)
                        connector.setBluetoothDevicesListCallback(null)
                        if (searchRetryCount < 12 && error.description.contains("busy", ignoreCase = true)) {
                            searchRetryCount += 1
                            Log.e(TAG, "search busy, retry #$searchRetryCount in 6s")
                            mainHandler.postDelayed({
                                if (generation == searchGeneration && gimbal == null) {
                                    startBluetoothSearch()
                                }
                            }, 6000)
                            return
                        }
                        setPhase("error")
                        pushEvent(
                            mapOf(
                                "type" to "error",
                                "message" to "bluetooth search failed: ${error.description}",
                            )
                        )
                    }
                }
            },
        )
        mainHandler.postDelayed({
            if (generation != searchGeneration || gimbal != null) return@postDelayed
            Log.e(TAG, "search timeout reached")
            if (bluetoothConnecting.remove(BLE_CONNECT_KEY)) {
                connector.setBluetoothDevicesListCallback(null)
                setPhase("disconnected")
                pushEvent(
                    mapOf(
                        "type" to "error",
                        "message" to "未发现云台：请短按 Osmo 电源键唤醒云台，App 会自动重连",
                    )
                )
            }
        }, BLUETOOTH_SEARCH_TIMEOUT_MS)
        return true
    }

    // ------------------------------------------------------------------ 云台控制

    private fun handleSetVelocity(call: MethodCall, result: MethodChannel.Result) {
        val yawDps = (call.argument<Double>("yawDps") ?: 0.0).toFloat()
        val pitchDps = (call.argument<Double>("pitchDps") ?: 0.0).toFloat()
        rotateWithCompletion(
            Rotation.Builder()
                .yaw(yawDps)
                .pitch(pitchDps)
                .roll(Rotation.NO_ROTATION)
                .mode(RotationMode.SPEED)
                .time(0.0)
                .build(),
            result,
        )
    }

    private fun handleStop(result: MethodChannel.Result) {
        // 以零速度 SPEED 指令代替官方 Sample 中的 rotate(null)：等价停转且类型安全。
        rotateWithCompletion(
            Rotation.Builder()
                .yaw(0f)
                .pitch(0f)
                .roll(Rotation.NO_ROTATION)
                .mode(RotationMode.SPEED)
                .time(0.0)
                .build(),
            result,
        )
    }

    private fun handleRotateTo(call: MethodCall, result: MethodChannel.Result) {
        val yawDeg = (call.argument<Double>("yawDeg") ?: 0.0).toFloat()
        val pitchDeg = (call.argument<Double>("pitchDeg") ?: 0.0).toFloat()
        val durationMs = (call.argument<Int>("durationMs") ?: 800).coerceIn(100, 5000)
        rotateWithCompletion(
            Rotation.Builder()
                .yaw(yawDeg)
                .pitch(pitchDeg)
                .roll(Rotation.NO_ROTATION)
                .mode(RotationMode.ABSOLUTE_ANGLE)
                .time(durationMs / 1000.0)
                .build(),
            result,
        )
    }

    private fun handleCenter(result: MethodChannel.Result) {
        rotateWithCompletion(
            Rotation.Builder()
                .yaw(0f)
                .pitch(0f)
                .roll(Rotation.NO_ROTATION)
                .mode(RotationMode.ABSOLUTE_ANGLE)
                .time(0.8)
                .build(),
            result,
        )
    }

    private var lastRotateLogAt = 0L

    private fun rotateWithCompletion(rotation: Rotation, result: MethodChannel.Result) {
        val currentGimbal = gimbal
        if (currentGimbal == null) {
            Log.e(TAG, "rotate: gimbal unavailable")
            result.error("gimbal_unavailable", "云台未连接", null)
            return
        }
        try {
            val now = System.currentTimeMillis()
            if (now - lastRotateLogAt > 1000) {
                lastRotateLogAt = now
                Log.i(
                    TAG,
                    "rotate: mode=${rotation.mode} yaw=${rotation.yaw} pitch=${rotation.pitch}",
                )
            }
            currentGimbal.rotate(
                rotation,
                object : CommonCallbacks.CompletionCallback<DJIError> {
                    override fun onResult(error: DJIError?) {
                        mainHandler.post {
                            val detail = "mode=${rotation.mode} yaw=${rotation.yaw} pitch=${rotation.pitch}"
                            Log.e(TAG, "rotate result: ${error?.description ?: "ok"} $detail")
                            if (error == null) {
                                result.success(null)
                            } else {
                                pushEvent(
                                    mapOf(
                                        "type" to "error",
                                        "message" to "rotate failed: ${error.description}",
                                    )
                                )
                                result.error("rotate_failed", error.description, detail)
                            }
                        }
                    }
                },
            )
        } catch (error: Exception) {
            result.error("rotate_failed", error.message, null)
        }
    }

    // ------------------------------------------------------------------ 状态推送

    private fun bindProduct(product: BaseProduct?) {
        if (product == null) {
            return
        }
        Log.e(TAG, "bindProduct: model=${product.model}")
        productName = product.model?.displayName ?: product.toString()
        if (product is HandHeld || product.gimbal != null) {
            val nextGimbal = product.gimbal
            if (nextGimbal != null) {
                gimbal = nextGimbal
                searchGeneration += 1
                bluetoothConnecting.clear()
                searchRetryCount = 0
                reconnectAttempts = 0
                DJISDKManager.getInstance().bluetoothProductConnector
                    ?.setBluetoothDevicesListCallback(null)
                setPhase("connected")
                try {
                    nextGimbal.setStateCallback(gimbalStateCallback)
                } catch (_: Exception) {
                }
            } else {
                setPhase("connected_no_gimbal")
            }
        } else {
            setPhase("connected_no_gimbal")
        }
    }

    private val gimbalStateCallback = GimbalState.Callback { gimbalState ->
        val now = System.currentTimeMillis()
        if (now - lastAttitudePushAt < ATTITUDE_PUSH_MIN_INTERVAL_MS) {
            return@Callback
        }
        lastAttitudePushAt = now
        val attitude = gimbalState.attitudeInDegrees
        pushEvent(
            mapOf(
                "type" to "attitude",
                "pitch" to attitude.pitch.toDouble(),
                "yaw" to attitude.yaw.toDouble(),
                "roll" to attitude.roll.toDouble(),
            )
        )
    }

    private fun setPhase(next: String) {
        Log.e(TAG, "phase -> $next")
        phase = next
        pushEvent(phasePayload())
    }

    private fun phasePayload(): Map<String, Any?> {
        return mapOf(
            "type" to "phase",
            "phase" to phase,
            "model" to productName,
            "hasGimbal" to (gimbal != null),
        )
    }

    private fun pushEvent(payload: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(payload) }
    }

    private fun statusPayload(): Map<String, Any> {
        return mapOf(
            "phase" to phase,
            "model" to productName,
            "hasGimbal" to (gimbal != null),
        )
    }

    private fun missingBluetoothPermissions(): List<String> {
        val activity = activity ?: return emptyList()
        fun granted(permission: String) =
            activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            buildList {
                if (!granted(Manifest.permission.BLUETOOTH_SCAN)) add(Manifest.permission.BLUETOOTH_SCAN)
                if (!granted(Manifest.permission.BLUETOOTH_CONNECT)) {
                    add(Manifest.permission.BLUETOOTH_CONNECT)
                }
            }
        } else {
            if (granted(Manifest.permission.ACCESS_FINE_LOCATION)) emptyList() else listOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        }
    }
}

private const val APP_REGISTER_KEY = "dji_app"
private const val BLE_CONNECT_KEY = "dji_ble_connect"
