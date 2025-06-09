
package com.example.xchange

import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.WifiManager
import android.net.wifi.WpsInfo
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "xchange/wifi_settings"
    private val TAG = "MainActivity"
    private var wifiP2pManager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var peerDiscoveryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiP2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        channel = wifiP2pManager?.initialize(this, Looper.getMainLooper(), null)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openWifiSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to open Wi-Fi settings: ${e.message}")
                        result.error("WIFI_SETTINGS_ERROR", "Failed to open Wi-Fi settings: ${e.message}", null)
                    }
                }
                "enableWifi" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        // Déconnecter de tout réseau Wi-Fi existant
                        if (wifiManager.isWifiEnabled) {
                            wifiManager.disconnect()
                            Log.d(TAG, "Disconnected from current Wi-Fi network")
                            Thread.sleep(1000) // Attendre la déconnexion
                        }
                        if (!wifiManager.isWifiEnabled) {
                            wifiManager.isWifiEnabled = true
                            Thread.sleep(2000) // Attendre l'activation
                            if (wifiManager.isWifiEnabled) {
                                Log.d(TAG, "Wi-Fi enabled successfully")
                                result.success(true)
                            } else {
                                Log.e(TAG, "Failed to enable Wi-Fi after attempt")
                                result.error(
                                    "WIFI_ENABLE_FAILED",
                                    "Failed to enable Wi-Fi. Please enable it manually.",
                                    null
                                )
                            }
                        } else {
                            Log.d(TAG, "Wi-Fi already enabled")
                            result.success(true)
                        }
                    } catch (e: SecurityException) {
                        Log.e(TAG, "Security exception enabling Wi-Fi: ${e.message}")
                        result.error(
                            "WIFI_SECURITY_ERROR",
                            "Permission denied to enable Wi-Fi: ${e.message}",
                            null
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Error enabling Wi-Fi: ${e.message}", e)
                        result.error("WIFI_ERROR", "Failed to enable Wi-Fi: ${e.message}", null)
                    }
                }
                "enableBluetooth" -> {
                    try {
                        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                        if (bluetoothAdapter == null) {
                            Log.e(TAG, "Bluetooth not supported")
                            result.error("BLUETOOTH_NOT_AVAILABLE", "Bluetooth is not supported.", null)
                        } else if (!bluetoothAdapter.isEnabled) {
                            bluetoothAdapter.enable()
                            Thread.sleep(2000)
                            if (bluetoothAdapter.isEnabled) {
                                Log.d(TAG, "Bluetooth enabled successfully")
                                result.success(true)
                            } else {
                                Log.w(TAG, "Failed to enable Bluetooth")
                                result.error(
                                    "BLUETOOTH_ENABLE_FAILED",
                                    "Failed to enable Bluetooth. Please enable it manually.",
                                    null
                                )
                            }
                        } else {
                            Log.d(TAG, "Bluetooth already enabled")
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception enabling Bluetooth: ${e.message}")
                        result.error("BLUETOOTH_ERROR", "Failed to enable Bluetooth: ${e.message}", null)
                    }
                }
                "isTetheringEnabled" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val isEnabled = wifiManager.isWifiEnabled
                        Log.d(TAG, "Tethering check (Wi-Fi enabled): $isEnabled")
                        result.success(isEnabled)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to check tethering: ${e.message}")
                        result.error("TETHERING_CHECK_ERROR", "Failed to check tethering: ${e.message}", null)
                    }
                }
                "openTetheringSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                        Log.d(TAG, "Opened tethering settings")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to open tethering settings: ${e.message}")
                        result.error("TETHERING_SETTINGS_ERROR", "Failed to open tethering settings: ${e.message}", null)
                    }
                }
                "openBluetoothSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        Log.d(TAG, "Opened Bluetooth settings")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to open Bluetooth settings: ${e.message}")
                        result.error("BLUETOOTH_SETTINGS_ERROR", "Failed to open Bluetooth settings: ${e.message}", null)
                    }
                }
                "createWifiP2pGroup" -> {
                    try {
                        Log.d(TAG, "Attempting to create Wi-Fi Direct group with WifiP2pManager")
                        wifiP2pManager?.createGroup(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "Wi-Fi Direct group created successfully")
                                result.success(true)
                            }
                            override fun onFailure(reason: Int) {
                                Log.e(TAG, "Failed to create Wi-Fi Direct group: $reason")
                                result.error("WIFI_P2P_ERROR", "Failed to create group: $reason", null)
                            }
                        })
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception while creating Wi-Fi Direct group: ${e.message}")
                        result.error("WIFI_P2P_ERROR", "Failed to create Wi-Fi Direct group: ${e.message}", null)
                    }
                }
                "discoverPeers" -> {
                    try {
                        Log.d(TAG, "Attempting to discover Wi-Fi Direct peers")
                        peerDiscoveryResult = result
                        wifiP2pManager?.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "Peer discovery started successfully")
                            }
                            override fun onFailure(reason: Int) {
                                Log.e(TAG, "Failed to start peer discovery: $reason")
                                peerDiscoveryResult?.error("PEER_DISCOVERY_ERROR", "Failed to discover peers: $reason", null)
                                peerDiscoveryResult = null
                            }
                        })
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception while discovering peers: ${e.message}")
                        result.error("PEER_DISCOVERY_ERROR", "Failed to discover peers: ${e.message}", null)
                    }
                }
                "joinWifiP2pGroup" -> {
                    try {
                        val deviceAddress = call.argument<String>("deviceAddress")
                        if (deviceAddress == null) {
                            result.error("INVALID_ARGUMENT", "Device address is required", null)
                            return@setMethodCallHandler
                        }
                        Log.d(TAG, "Attempting to join Wi-Fi Direct group with device: $deviceAddress")
                        val config = WifiP2pConfig().apply {
                            this.deviceAddress = deviceAddress
                            wps.setup = WpsInfo.PBC
                        }
                        wifiP2pManager?.connect(channel, config, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "Successfully initiated connection to group")
                                result.success(true)
                            }
                            override fun onFailure(reason: Int) {
                                Log.e(TAG, "Failed to join group: $reason")
                                result.error("JOIN_GROUP_ERROR", "Failed to join group: $reason", null)
                            }
                        })
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception while joining Wi-Fi Direct group: ${e.message}")
                        result.error("JOIN_GROUP_ERROR", "Failed to join Wi-Fi Direct group: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Enregistrer un écouteur pour les pairs découverts
        wifiP2pManager?.requestPeers(channel) { peers: WifiP2pDeviceList? ->
            if (peers != null) {
                val peerList = peers.deviceList.map { device ->
                    mapOf(
                        "deviceName" to (device.deviceName ?: "Unknown"),
                        "deviceAddress" to device.deviceAddress,
                        "status" to device.status,
                        "isGroupOwner" to device.isGroupOwner
                    )
                }
                Log.d(TAG, "Discovered peers: $peerList")
                peerDiscoveryResult?.success(peerList)
            } else {
                Log.e(TAG, "No peers found")
                peerDiscoveryResult?.success(emptyList<Map<String, Any>>())
            }
            peerDiscoveryResult = null
        }
    }
}