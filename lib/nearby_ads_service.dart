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
  StreamSubscription<List<ScanResult>>? _scanSub;

  static const String _serviceUuid = '0000feed-0000-1000-8000-00805f9b34fb';

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
            incomingAds.add(ad);
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
    final data = utf8.encode(jsonEncode(ad.toJson()));
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
