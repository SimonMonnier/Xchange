package com.example.xchange

import android.content.Context
import android.net.wifi.aware.*
import android.os.Build
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
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        wifiAwareManager = getSystemService(Context.WIFI_AWARE_SERVICE) as WifiAwareManager

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
        wifiAwareManager?.attach(object : AttachCallback() {
            override fun onAttached(session: WifiAwareSession) {
                val config = PublishConfig.Builder()
                    .setServiceName("aware_msg")
                    .setServiceSpecificInfo(message.toByteArray())
                    .build()
                session.publish(config, object : DiscoverySessionCallback() {}, null)
            }
        }, null)
    }

    private fun startSubscribing() {
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
        }, null)
    }
}
