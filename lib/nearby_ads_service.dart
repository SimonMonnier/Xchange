import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'ad_http_server.dart';
import 'voip_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

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
  final Map<String, ScanResult> _resultMap = {};
  final AdHttpServer _httpServer = AdHttpServer();
  final VoipService voipService = VoipService();
  final FlutterP2pHost _p2pHost = FlutterP2pHost();
  final FlutterP2pClient _p2pClient = FlutterP2pClient();

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
        await _p2pHost.initialize();
        await _p2pClient.initialize();
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
                  _resultMap[ad.id] = result;
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
              _resultMap[ad.id] = result;
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
    Uint8List? imageBytes,
  }) async {
    final ip = await _getLocalIp();
    final ad = Announcement(
      id: const Uuid().v4(),
      title: title,
      description: description,
      price: price,
      imageBase64: imageBytes != null ? base64Encode(imageBytes) : null,
      ip: ip,
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
    // If another announcement is currently being advertised, stop it first
    if (selected != null) {
      await stopAdvertising();
    }
    await startAdvertising(ad);
  }

  Future<void> startAdvertising(Announcement ad) async {
    // Ensure any previous advertisement is stopped before starting a new one
    if (selected != null) {
      await stopAdvertising();
    }
    // Ensure Wi-Fi Direct permissions are granted before creating the group
    if (!await _p2pHost.checkP2pPermissions()) {
      await _p2pHost.askP2pPermissions();
      if (!await _p2pHost.checkP2pPermissions()) {
        state = AdsState.permissionDenied;
        notifyListeners();
        return;
      }
    }
    selected = ad;
    final hostState = await _p2pHost.createGroup(advertise: false);
    final updated = Announcement(
      id: ad.id,
      title: ad.title,
      description: ad.description,
      price: ad.price,
      imageBase64: null,
      ip: hostState.hostIpAddress ?? await _getLocalIp(),
      ssid: hostState.ssid,
      psk: hostState.preSharedKey,
    );
    final jsonStr = jsonEncode(updated.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    await _httpServer.start(ad);
    selected = updated;
    await voipService.startServer();
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
    await _p2pHost.removeGroup();
    await _peripheral.stop();
    await _httpServer.stop();
    await voipService.dispose();
    notifyListeners();
  }

  Future<Announcement?> fetchFullAnnouncement(String id) async {
    final ad = receivedAnnouncements
        .firstWhere((a) => a.id == id, orElse: () => Announcement(
            id: '', title: '', description: '', price: 0));
    if (ad.id.isEmpty || ad.ip == null) return null;
    if (ad.ssid != null && ad.psk != null) {
      try {
        await _p2pClient.connectWithCredentials(ad.ssid!, ad.psk!);
      } catch (_) {}
    }
    try {
      final resp = await http
          .get(Uri.parse('http://${ad.ip}:8081/announcement'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        return Announcement.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> callAnnouncement(Announcement ad) async {
    if (ad.ssid != null && ad.psk != null) {
      try {
        await _p2pClient.connectWithCredentials(ad.ssid!, ad.psk!);
      } catch (_) {}
    }
    if (ad.ip != null) {
      await voipService.call(ad.ip!);
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

  Future<String?> _getLocalIp() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
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
    await _p2pClient.disconnect();
    await _p2pHost.dispose();
    await _p2pClient.dispose();
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }
}
