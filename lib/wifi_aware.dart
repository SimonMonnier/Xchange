import 'dart:async';
import 'package:flutter/services.dart';

class WifiAware {
  static const MethodChannel _channel = MethodChannel('wifi_aware');
  static const EventChannel _eventChannel = EventChannel('wifi_aware/messages');

  static Future<void> startPublishing(String message) {
    return _channel.invokeMethod('startPublishing', {'message': message});
  }

  static Future<void> startSubscribing() {
    return _channel.invokeMethod('startSubscribing');
  }

  static Stream<String> get messages =>
      _eventChannel.receiveBroadcastStream().map((event) => event as String);
}
