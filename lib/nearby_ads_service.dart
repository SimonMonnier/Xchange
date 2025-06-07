import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/announcement.dart';

/// Represents the current initialization status of [NearbyAdsService].
///
/// * [idle] - the service is not yet initialized.
/// * [ready] - initialization succeeded and the service can advertise/scan.
/// * [permissionDenied] - required permissions were not granted and the
///   service cannot operate.
enum AdsState { idle, ready, permissionDenied }

class NearbyAdsService extends ChangeNotifier {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  AdsState state = AdsState.idle;
  final List<String> receivedAnnouncements = [];
  final List<Announcement> announcements = [];
  Announcement? selected;

  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  static const int _manufacturerId = 0xFFFF;

  Future<void> initialize() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (statuses.values.any((s) => !s.isGranted)) {
      state = AdsState.permissionDenied;
      notifyListeners();
      return;
    }

    await _loadAnnouncements();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final data = result.advertisementData.manufacturerData[_manufacturerId];
        if (data != null) {
          final text = utf8.decode(data);
          if (!receivedAnnouncements.contains(text)) {
            receivedAnnouncements.add(text);
            notifyListeners();
          }
        }
      }
    });

    await FlutterBluePlus.turnOn();
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first;

    _startScanning();
    state = AdsState.ready;
    notifyListeners();
  }

  Future<void> addAnnouncement(String text) async {
    final ad = Announcement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
    );
    announcements.add(ad);
    await _saveAnnouncements();
    notifyListeners();
  }

  Future<void> removeAnnouncement(Announcement ad) async {
    if (selected?.id == ad.id) {
      await stopAdvertising();
    }
    announcements.removeWhere((a) => a.id == ad.id);
    await _saveAnnouncements();
    notifyListeners();
  }

  Future<void> selectAnnouncement(Announcement? ad) async {
    if (ad == null) {
      await stopAdvertising();
      return;
    }
    await startAdvertising(ad);
  }

  Future<void> startAdvertising(Announcement ad) async {
    selected = ad;
    final bytes = Uint8List.fromList(utf8.encode(ad.text));
    await _peripheral.start(
      advertiseData: AdvertiseData(
        manufacturerId: _manufacturerId,
        manufacturerData: bytes,
        includeDeviceName: false,
      ),
    );
    notifyListeners();
  }

  Future<void> stopAdvertising() async {
    selected = null;
    await _peripheral.stop();
    notifyListeners();
  }

  void _startScanning() {
    _scan();
    _scanTimer = Timer.periodic(const Duration(minutes: 1), (_) => _scan());
  }

  void _scan() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  Future<void> _saveAnnouncements() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(announcements.map((e) => e.toJson()).toList());
    await prefs.setString('announcements', json);
  }

  Future<void> _loadAnnouncements() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('announcements');
    if (json == null) return;
    final List data = jsonDecode(json);
    announcements
        .addAll(data.map((e) => Announcement.fromJson(e)).toList());
  }

  Future<void> _stop() async {
    await stopAdvertising();
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanTimer?.cancel();
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }
}
