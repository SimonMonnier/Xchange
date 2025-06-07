import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

import 'models/announcement.dart';

class _ChunkAssembly {
  final int total;
  int received = 0;
  final List<List<int>?> chunks;

  _ChunkAssembly(this.total) : chunks = List.filled(total, null);

  bool add(int index, List<int> data) {
    if (index >= total) return false;
    if (chunks[index] == null) {
      chunks[index] = data;
      received++;
    }
    return received == total;
  }

  Uint8List merge() => Uint8List.fromList(chunks.expand((c) => c!).toList());
}

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
  final List<Announcement> receivedAnnouncements = [];
  final List<Announcement> announcements = [];
  Announcement? selected;

  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _advertiseTimer;
  List<Uint8List> _advertiseChunks = [];
  int _advertiseIndex = 0;
  final Map<int, _ChunkAssembly> _assemblies = {};

  static const int _manufacturerId = 0xFFFF;

  Future<void> initialize() async {
    AdsState targetState = AdsState.ready;
    try {
      int sdkInt = 0;
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        sdkInt = info.version.sdkInt;
      }

      final permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ];
      if (sdkInt <= 30) {
        permissions.add(Permission.locationWhenInUse);
      }

      final statuses = await permissions.request();
      if (statuses.values.any((s) => !s.isGranted)) {
        targetState = AdsState.permissionDenied;
      } else {
        await _loadAnnouncements();

        try {
          _scanSub = FlutterBluePlus.scanResults.listen((results) {
            for (final result in results) {
              final data =
                  result.advertisementData.manufacturerData[_manufacturerId];
              if (data != null) {
                _processData(Uint8List.fromList(data));
              }
            }
          });

          await FlutterBluePlus.turnOn().timeout(const Duration(seconds: 5));
          await FlutterBluePlus.adapterState
              .where((s) => s == BluetoothAdapterState.on)
              .first
              .timeout(const Duration(seconds: 5));

          _startScanning();
        } catch (_) {
          // Ignore failures to enable Bluetooth or start scanning
        }
      }
    } catch (_) {
      // unexpected error, stay in idle state
    }

    state = targetState;
    notifyListeners();
    await _loadAnnouncements();

    state = AdsState.ready;
    notifyListeners();

    try {
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final data =
              result.advertisementData.manufacturerData[_manufacturerId];
          if (data != null) {
            _processData(Uint8List.fromList(data));
          }
        }
      });

      await FlutterBluePlus.turnOn().timeout(const Duration(seconds: 5));
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));

      _startScanning();
    } catch (_) {
      // Ignore failures to enable Bluetooth or start scanning
    }
  }

  Future<void> addAnnouncement({
    required String title,
    required String description,
    required double price,
    String? imageUrl,
    String? imageBase64,
  }) async {
    final ad = Announcement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      price: price,
      imageUrl: imageUrl,
      imageBase64: imageBase64,
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

  void removeReceivedAnnouncement(Announcement ad) {
    receivedAnnouncements.removeWhere((a) => a.id == ad.id);
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
    final jsonStr = jsonEncode(ad.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    const payloadSize = 20;
    final total = (bytes.length / payloadSize).ceil();
    final idInt = int.tryParse(ad.id) ?? ad.id.hashCode;
    _advertiseChunks = List.generate(total, (i) {
      final start = i * payloadSize;
      final end = (start + payloadSize > bytes.length)
          ? bytes.length
          : start + payloadSize;
      final slice = bytes.sublist(start, end);
      return Uint8List.fromList([
        i,
        total,
        (idInt >> 24) & 0xFF,
        (idInt >> 16) & 0xFF,
        (idInt >> 8) & 0xFF,
        idInt & 0xFF,
        ...slice,
      ]);
    });
    _advertiseIndex = 0;
    _advertiseTimer?.cancel();
    await _sendAdvertiseChunk();
    _advertiseTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _sendAdvertiseChunk());
    notifyListeners();
  }

  Future<void> _sendAdvertiseChunk() async {
    if (_advertiseChunks.isEmpty) return;
    final data = _advertiseChunks[_advertiseIndex];
    _advertiseIndex = (_advertiseIndex + 1) % _advertiseChunks.length;
    // Stop the previous advertisement before starting a new one to
    // avoid "ADVERTISE_FAILED_TOO_MANY_ADVERTISERS" errors on Android.
    await _peripheral.stop();
    await _peripheral.start(
      advertiseData: AdvertiseData(
        manufacturerId: _manufacturerId,
        manufacturerData: data,
        includeDeviceName: false,
      ),
    );
  }

  void _processData(Uint8List data) {
    if (data.length < 6) return;
    final index = data[0];
    final total = data[1];
    final id = (data[2] << 24) |
        (data[3] << 16) |
        (data[4] << 8) |
        data[5];
    final chunk = data.sublist(6);
    final assembly = _assemblies.putIfAbsent(id, () => _ChunkAssembly(total));
    if (assembly.add(index, chunk)) {
      final bytes = assembly.merge();
      _assemblies.remove(id);
      try {
        final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final ad = Announcement.fromJson(map);
        if (receivedAnnouncements.every((e) => e.id != ad.id)) {
          receivedAnnouncements.add(ad);
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  Future<void> stopAdvertising() async {
    selected = null;
    await _peripheral.stop();
    _advertiseTimer?.cancel();
    _advertiseChunks = [];
    notifyListeners();
  }

  void _startScanning() {
    _scan();
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) => _scan());
  }

  void _scan() async {
    // Restart scanning cleanly to avoid "could not find callback wrapper" errors
    // when multiple scans overlap.
    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
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
    _advertiseTimer?.cancel();
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }
}
