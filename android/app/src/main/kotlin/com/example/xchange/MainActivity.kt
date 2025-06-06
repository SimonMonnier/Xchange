package com.example.xchange

import android.content.Context
import android.net.wifi.aware.*
import android.util.Log
import android.os.Build
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.ParcelUuid
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

@RequiresApi(Build.VERSION_CODES.O)
class MainActivity : FlutterActivity() {
    private val channel = "wifi_aware"
    private val eventChannel = "wifi_aware/messages"

    private var wifiAwareManager: WifiAwareManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleScanner: BluetoothLeScanner? = null
    private val serviceUuid = ParcelUuid.fromString("c8d19b8c-e4cb-4365-af30-f0507a1c72e6")
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        wifiAwareManager = getSystemService(Context.WIFI_AWARE_SERVICE) as? WifiAwareManager
        if (wifiAwareManager == null) {
            Log.e("MainActivity", "Wi-Fi Aware not supported on this device")
        }
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        bleScanner = bluetoothAdapter?.bluetoothLeScanner


        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        bleScanner = bluetoothAdapter?.bluetoothLeScanner

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPublishing" -> {
                    val message = call.argument<String>("message") ?: ""
                    startPublishing(message)
                    result.success(null)
                }
                "startSubscribing" -> {
                    startSubscribing()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun startPublishing(message: String) {
        if (wifiAwareManager != null) {
            wifiAwareManager?.attach(object : AttachCallback() {
                override fun onAttached(session: WifiAwareSession) {
                    val config = PublishConfig.Builder()
                        .setServiceName("aware_msg")
                        .setServiceSpecificInfo(message.toByteArray())
                        .build()
                    session.publish(config, object : DiscoverySessionCallback() {}, null)
                }
            }, null)
        } else {
            if (bleAdvertiser == null) {
                Log.e("MainActivity", "Bluetooth LE advertising not supported")
                return

        if (wifiAwareManager == null) {
            Log.e("MainActivity", "Wi-Fi Aware not supported; cannot publish.")
            return
        }
        wifiAwareManager?.attach(object : AttachCallback() {
            override fun onAttached(session: WifiAwareSession) {
                val config = PublishConfig.Builder()
                    .setServiceName("aware_msg")
                    .setServiceSpecificInfo(message.toByteArray())
                    .build()
                session.publish(config, object : DiscoverySessionCallback() {}, null)

            }
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false)
                .build()
            val data = AdvertiseData.Builder()
                .addServiceUuid(serviceUuid)
                .addServiceData(serviceUuid, message.toByteArray())
                .build()
            bleAdvertiser?.startAdvertising(settings, data, object : AdvertiseCallback() {
                override fun onStartFailure(errorCode: Int) {
                    Log.e("MainActivity", "BLE advertise failed: $errorCode")
                }
            })
        }
    }

    private fun startSubscribing() {
        if (wifiAwareManager != null) {
            wifiAwareManager?.attach(object : AttachCallback() {
                override fun onAttached(session: WifiAwareSession) {
                    val config = SubscribeConfig.Builder()
                        .setServiceName("aware_msg")
                        .build()
                    session.subscribe(config, object : DiscoverySessionCallback() {
                        override fun onServiceDiscovered(
                            peerHandle: PeerHandle,
                            serviceSpecificInfo: ByteArray,
                            matchFilter: MutableList<ByteArray>?
                        ) {
                            val msg = String(serviceSpecificInfo)
                            eventSink?.success(msg)
                        }
                    }, null)
                }
            }, null)
        } else {
            if (bleScanner == null) {
                Log.e("MainActivity", "Bluetooth LE scanning not supported")
                return

        if (wifiAwareManager == null) {
            Log.e("MainActivity", "Wi-Fi Aware not supported; cannot subscribe.")
            return
        }
        wifiAwareManager?.attach(object : AttachCallback() {
            override fun onAttached(session: WifiAwareSession) {
                val config = SubscribeConfig.Builder()
                    .setServiceName("aware_msg")
                    .build()
                session.subscribe(config, object : DiscoverySessionCallback() {
                    override fun onServiceDiscovered(peerHandle: PeerHandle, serviceSpecificInfo: ByteArray, matchFilter: MutableList<ByteArray>?) {
                        val msg = String(serviceSpecificInfo)
                        eventSink?.success(msg)
                    }
                }, null)

            }
            val filter = ScanFilter.Builder().setServiceUuid(serviceUuid).build()
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            bleScanner?.startScan(listOf(filter), settings, object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    val data = result.scanRecord?.getServiceData(serviceUuid) ?: return
                    val msg = String(data)
                    eventSink?.success(msg)
                }
            })
        }
    }
}
