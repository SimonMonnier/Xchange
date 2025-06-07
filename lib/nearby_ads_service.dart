import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nearby_service/nearby_service.dart';

import 'models/sale_ad.dart';

enum AdsState { idle, discovering, connected }

class NearbyAdsService extends ChangeNotifier {
  final NearbyService _nearby = NearbyService.getInstance();

  AdsState state = AdsState.idle;
  List<NearbyDevice> peers = [];
  NearbyDevice? _connectedDevice;
  final List<SaleAd> incomingAds = [];

  StreamSubscription? _peersSub;

  Future<void> initialize() async {
    await _nearby.initialize();
    await _nearby.discover();
    _peersSub = _nearby.getPeersStream().listen((event) {
      peers = event;
      notifyListeners();
    });
    state = AdsState.discovering;
    notifyListeners();
  }

  Future<void> connect(NearbyDevice device) async {
    final res = await _nearby.connectById(device.info.id);
    if (res || device.status.isConnected) {
      _startChannel(device);
    }
  }

  void _startChannel(NearbyDevice device) {
    _connectedDevice = device;
    _nearby.startCommunicationChannel(
      NearbyCommunicationChannelData(
        device.info.id,
        messagesListener: NearbyServiceMessagesListener(
          onData: _handleMessage,
        ),
      ),
    );
    state = AdsState.connected;
    notifyListeners();
  }

  void _handleMessage(ReceivedNearbyMessage msg) {
    msg.content.byType(
      onTextRequest: (request) {
        try {
          final data = jsonDecode(request.value) as Map<String, dynamic>;
          final ad = SaleAd.fromJson(data);
          incomingAds.add(ad);
          notifyListeners();
          if (_connectedDevice != null) {
            _nearby.send(
              OutgoingNearbyMessage(
                receiver: _connectedDevice!.info,
                content: NearbyMessageTextResponse(id: request.id),
              ),
            );
          }
        } catch (_) {}
      },
    );
  }

  Future<void> sendAd(SaleAd ad) async {
    if (_connectedDevice == null) return;
    final jsonStr = jsonEncode(ad.toJson());
    await _nearby.send(
      OutgoingNearbyMessage(
        receiver: _connectedDevice!.info,
        content: NearbyMessageTextRequest.create(value: jsonStr),
      ),
    );
  }
}
