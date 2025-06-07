import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'dart:io';

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
  final FlutterP2pHost _host = FlutterP2pHost();
  final FlutterP2pClient _client = FlutterP2pClient();

  AdsState state = AdsState.idle;
  final List<Announcement> receivedAnnouncements = [];
  final List<Announcement> announcements = [];
  Announcement? selected;

  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

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
                final jsonStr = utf8.decode(data);
                try {
                  final map = jsonDecode(jsonStr) as Map<String, dynamic>;
                  final ad = Announcement.fromJson(map);
                  if (receivedAnnouncements
                      .every((existing) => existing.id != ad.id)) {
                    receivedAnnouncements.add(ad);
                    notifyListeners();
                  }
                } catch (_) {
                  // ignore malformed data
                }
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
            final jsonStr = utf8.decode(data);
            try {
              final map = jsonDecode(jsonStr) as Map<String, dynamic>;
              final ad = Announcement.fromJson(map);
              if (receivedAnnouncements
                  .every((existing) => existing.id != ad.id)) {
                receivedAnnouncements.add(ad);
                notifyListeners();
              }
            } catch (_) {
              // ignore malformed data
            }
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
    String? phone,
  }) async {
    final ad = Announcement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      price: price,
      imageUrl: imageUrl,
      phone: phone,
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
    final jsonStr = jsonEncode(ad.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    await _peripheral.start(
      advertiseData: AdvertiseData(
        manufacturerId: _manufacturerId,
        manufacturerData: bytes,
        includeDeviceName: false,
      ),
    );
    try {
      await _host.initialize();
      await _host.createGroup();
    } catch (_) {
      // ignore failures to start Wi-Fi Direct host
    }
    notifyListeners();
  }

  Future<void> stopAdvertising() async {
    selected = null;
    await _peripheral.stop();
    try {
      await _host.removeGroup();
    } catch (_) {
      // ignore failures during cleanup
    }
    notifyListeners();
  }

  Future<void> callAdvertiser(Announcement ad) async {
    try {
      await _client.initialize();
      await _client.startScan((devices) async {
        for (final device in devices) {
          if (device.deviceName == ad.id) {
            await _client.stopScan();
            try {
              await _client.connectWithDevice(device);
            } catch (_) {}
            break;
          }
        }
      });
    } catch (_) {
      // ignore wifi direct errors
    }
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
