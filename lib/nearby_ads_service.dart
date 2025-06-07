import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/sale_ad.dart';

enum AdsState { idle, ready }

class NearbyAdsService extends ChangeNotifier {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  AdsState state = AdsState.idle;
  final List<SaleAd> incomingAds = [];
  final Map<String, SaleAd> _adsById = {};
  StreamSubscription<List<ScanResult>>? _scanSub;

  SaleAd? _currentAd;

  static const String _serviceUuid = '0000feed-0000-1000-8000-00805f9b34fb';

  NearbyAdsService() {
    unawaited(initialize());
  }

  Future<void> initialize() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (statuses.values.any((s) => !s.isGranted)) {
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!hasListeners) return;

      for (final result in results) {
        final bytes =
            result.advertisementData.serviceData[Guid(_serviceUuid)];
        if (bytes != null) {
          try {
            final jsonStr = utf8.decode(bytes);
            final ad = SaleAd.fromJson(
              jsonDecode(jsonStr) as Map<String, dynamic>,
            );
            if (_adsById.containsKey(ad.id)) continue;
            incomingAds.add(ad);
            _adsById[ad.id] = ad;
            unawaited(_advertise(ad));
            notifyListeners();
          } catch (_) {}
        }
      }
    });
    await FlutterBluePlus.turnOn();
    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first;
    await FlutterBluePlus.startScan(withServices: [Guid(_serviceUuid)]);
    state = AdsState.ready;
    notifyListeners();
  }

  Future<void> publishAd(SaleAd ad) async {
    incomingAds.add(ad);
    _adsById[ad.id] = ad;
    await _advertise(ad);
    notifyListeners();
  }

  Future<void> _advertise(SaleAd ad) async {
    _currentAd = ad;
    final data = utf8.encode(jsonEncode(ad.toJson()));
    await _peripheral.stop();
    await _peripheral.start(
      advertiseData: AdvertiseData(
        serviceDataUuid: _serviceUuid,
        serviceData: data,
        includeDeviceName: false,
      ),
    );
  }

  Future<void> _stop() async {
    await _peripheral.stop();
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }
}
