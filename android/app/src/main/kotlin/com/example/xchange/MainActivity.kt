import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.WifiManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "xchange/wifi_settings"
    private var wifiP2pManager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiP2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        channel = wifiP2pManager?.initialize(this, mainLooper, null)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openWifiSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WIFI_SETTINGS_ERROR", "Failed to open Wi-Fi settings: ${e.message}", null)
                    }
                }
                "enableWifi" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                        if (!wifiManager.isWifiEnabled) {
                            wifiManager.isWifiEnabled = true
                            Thread.sleep(150) // Attendre pour l'état
                            if (wifiManager.isWifiEnabled) {
                                result.success(true)
                            } else {
                                result.error(
                                    "WIFI_ENABLE_FAILED",
                                    "Failed to enable Wi-Fi. Please enable it manually.",
                                    null
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    } catch (e: SecurityException) {
                        result.error(
                            "WIFI_SECURITY_ERROR",
                            "Permission denied to enable Wi-Fi: ${e.message}",
                            null
                        )
                    } catch (e: Exception) {
                        result.error("WIFI_ERROR", "Failed to enable Wi-Fi: ${e.message}", null)
                    }
                }
                "enableBluetooth" -> {
                    try {
                        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                        if (bluetoothAdapter == null) {
                            result.error("BLUETOOTH_NOT_AVAILABLE", "Bluetooth is not supported.", null)
                        } else if (!bluetoothAdapter.isEnabled) {
                            bluetoothAdapter.enable()
                            Thread.sleep(150)
                            if (bluetoothAdapter.isEnabled) {
                                result.success(true)
                            } else {
                                result.error(
                                    "BLUETOOTH_ENABLE_FAILED",
                                    "Failed to enable Bluetooth. Please enable it manually.",
                                    null
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", "Failed to enable Bluetooth: ${e.message}", null)
                    }
                }
                "isTetheringEnabled" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                        result.success(wifiManager.isWifiEnabled) // Simplifié
                    } catch (e: Exception) {
                        result.error("TETHERING_CHECK_ERROR", "Failed to check tethering: ${e.message}", null)
                    }
                }
                "openTetheringSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TETHERING_SETTINGS_ERROR", "Failed to open tethering settings: ${e.message}", null)
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_SETTINGS_ERROR", "Failed to open Bluetooth settings: ${e.message}", null)
                    }
                }
                "createWifiP2pGroup" -> {
                    try {
                        wifiP2pManager?.createGroup(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                developer.log("Groupe Wi-Fi Direct créé avec succès")
                                result.success(true)
                            }
                            override fun onFailure(reason: Int) {
                                developer.log("Échec de la création du groupe Wi-Fi Direct : $reason")
                                result.error("WIFI_P2P_ERROR", "Failed to create group: $reason}", null)
                            }
                        })
                    } catch (e: Exception) {
                        result.error("WIFI_P2P_ERROR", "Failed to create Wi-Fi Direct group: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}