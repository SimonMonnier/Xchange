package com.example.xchange

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.net.wifi.WifiManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "xchange/wifi_settings"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openWifiSettings" -> {
                    startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                    result.success(null)
                }
                "enableWifi" -> {
                    val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                    if (!wifiManager.isWifiEnabled) {
                        wifiManager.isWifiEnabled = true
                    }
                    result.success(null)
                }
                "enableBluetooth" -> {
                    val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                    if (bluetoothAdapter != null && !bluetoothAdapter.isEnabled) {
                        bluetoothAdapter.enable()
                    }
                    result.success(null)
                }
                "isTetheringEnabled" -> {
                    val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                    result.success(wifiManager.isWifiEnabled) // Simplified check, improve if needed
                }
                "openTetheringSettings" -> {
                    startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}