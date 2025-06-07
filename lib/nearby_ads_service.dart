import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_nearby_messages_api/flutter_nearby_messages_api.dart';

import 'models/sale_ad.dart';

enum AdsState { idle, ready }

class NearbyAdsService extends ChangeNotifier {
  final FlutterNearbyMessagesApi _nearby = FlutterNearbyMessagesApi();

  AdsState state = AdsState.idle;
  bool _publishing = false;
  bool _subscribed = false;
  final List<SaleAd> incomingAds = [];

  Future<void> initialize({required String apiKey}) async {
    await _nearby.setAPIKey(apiKey);
    _nearby.onFound = (msg) {
      try {
        final data = jsonDecode(msg) as Map<String, dynamic>;
        incomingAds.add(SaleAd.fromJson(data));
        notifyListeners();
      } catch (_) {}
    };
    _nearby.onLost = (_) {};
    await _nearby.backgroundSubscribe();
    _subscribed = true;
    state = AdsState.ready;
    notifyListeners();
  }

  Future<void> publishAd(SaleAd ad) async {
    final jsonStr = jsonEncode(ad.toJson());
    await _nearby.publish(jsonStr);
    _publishing = true;
  }

  Future<void> _stop() async {
    if (_publishing) {
      await _nearby.unPublish();
      _publishing = false;
    }
    if (_subscribed) {
      await _nearby.backgroundUnsubscribe();
      _subscribed = false;
    }
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }
}
