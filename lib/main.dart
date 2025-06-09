import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

/// Palette de couleurs futuristes
const Color neonBlue = Color(0xFF00DDEB);
const Color neonPurple = Color(0xFF7B00FF);
const Color darkBackground = Color(0xFF0A0A1F);
const Color accentGlow = Color(0xFF00FF88);

class Announcement {
  final String id;
  final String title;
  final String description;
  final String broadcasterId;
  final String broadcasterName;
  final String deviceAddress;
  final String? imageBase64;
  final String category;
  Uint8List? _imageBytes;

  Uint8List? get imageBytes {
    if (_imageBytes == null && imageBase64 != null) {
      _imageBytes = base64Decode(imageBase64!);
    }
    return _imageBytes;
  }

  Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.broadcasterId,
    required this.broadcasterName,
    required this.deviceAddress,
    this.imageBase64,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'broadcasterId': broadcasterId,
    'broadcasterName': broadcasterName,
    'deviceAddress': deviceAddress,
    'imageBase64': imageBase64,
    'category': category,
    'type': 'announcement',
  };

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    broadcasterId: json['broadcasterId'],
    broadcasterName: json['broadcasterName'],
    deviceAddress: json['deviceAddress'],
    imageBase64: json['imageBase64'],
    category: json['category'] ?? 'Autres',
  );
}

class AnnouncementProvider with ChangeNotifier {
  List<Announcement> _createdAnnouncements = [];
  List<Announcement> _receivedAnnouncements = [];
  final String deviceId = const Uuid().v4();
  String deviceName = 'Utilisateur';
  final FlutterP2pHost p2p = FlutterP2pHost();
  List<P2pClientInfo> peers = [];
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isInitialized = false;
  bool _isServerStarted = false;
  Completer<void>? _completer;
  Set<String> _selectedCategories = {'Autres'};

  static const List<String> categories = [
    'Vente',
    'Immobilier',
    'Véhicules',
    'Services',
    'Emploi',
    'Rencontres',
    'Fêtes',
    'Dons',
    'Restauration',
    'Loisirs',
    'Animaux',
    'Perdu/Trouvé',
    'Éducation',
    'Santé/Bien-être',
    'Voyages',
    'Autres',
  ];

  Future<void> get initializationDone {
    _completer ??= Completer<void>();
    return _completer!.future;
  }

  bool get isInitialized => _isInitialized;
  bool get isServerStarted => _isServerStarted;
  static const MethodChannel _channel = MethodChannel('xchange/wifi_settings');

  List<Announcement> get createdAnnouncements => _createdAnnouncements;
  List<Announcement> get receivedAnnouncements => _receivedAnnouncements
      .where((ann) => _selectedCategories.contains(ann.category))
      .toList();
  Set<String> get selectedCategories => _selectedCategories;

  AnnouncementProvider() {
    initialize();
  }

  void updateSelectedCategories(Set<String> newCategories) {
    _selectedCategories = newCategories.isNotEmpty ? newCategories : {'Autres'};
    notifyListeners();
  }

  Future<void> initialize() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = Platform.isAndroid
        ? await deviceInfo.androidInfo
        : null;
    final sdkInt = androidInfo?.version.sdkInt ?? 0;

    final permissions = <Permission>[
      Permission.location,
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.notification,
    ];

    if (sdkInt >= 33) {
      permissions.add(Permission.nearbyWifiDevices);
    }

    // Vérification explicite de NEARBY_WIFI_DEVICES pour Android 13+
    if (sdkInt >= 33 && !(await Permission.nearbyWifiDevices.isGranted)) {
      developer.log('NEARBY_WIFI_DEVICES permission not granted');
      _showErrorSnackBar(
        'Please grant Nearby Wi-Fi Devices permission to use Wi-Fi Direct.',
        actionLabel: 'Settings',
        action: () => openAppSettings(),
      );
      _completer?.complete();
      return;
    }

    // Demander les permissions
    final statuses = await permissions.request();
    bool allPermissionsGranted = statuses.values.every(
      (status) => status.isGranted,
    );

    if (!allPermissionsGranted) {
      developer.log('Required permissions not granted');
      _showErrorSnackBar(
        'Please grant all necessary permissions (location, microphone, nearby devices, etc.) to use app features.',
        actionLabel: 'Settings',
        action: () => openAppSettings(),
      );
      _completer?.complete();
      return;
    }

    // Vérifier Wi-Fi, Bluetooth et Tethering
    try {
      await _ensureWifiAndBluetoothEnabled();
      final isTetheringEnabled = await _channel.invokeMethod(
        'isTetheringEnabled',
      );
      if (!(isTetheringEnabled as bool)) {
        developer.log('Tethering is disabled');
        _showErrorSnackBar(
          'Tethering is disabled. Please enable it in Wi-Fi settings.',
          actionLabel: 'Open Tethering Settings',
          action: () => _channel.invokeMethod('openTetheringSettings'),
        );
        _completer?.complete();
        return;
      }
    } catch (e) {
      developer.log('Error enabling Wi-Fi/Bluetooth/Tethering: $e');
      _showErrorSnackBar('Please enable Wi-Fi, Bluetooth, and tethering.');
      _completer?.complete();
      return;
    }

    int retries = 3;
    while (retries > 0 && !_isInitialized) {
      developer.log(
        'Attempting Wi-Fi Direct initialization, retries left: $retries',
      );
      try {
        p2p.initialize();
        await createGroupWithRetry();
        _isServerStarted = true;
        developer.log('P2P group created successfully');

        // Configurer les listeners pour les messages et les clients
        p2p.streamReceivedTexts().listen(
          (message) async {
            try {
              final data = jsonDecode(message);
              if (data['type'] == 'announcement') {
                final announcement = await parseAnnouncement(data);
                addReceivedAnnouncement(announcement);
              } else if (data['type'] == 'offer') {
                _handleOffer(data['sdp'], data['from'], data['to']);
              } else if (data['type'] == 'answer') {
                _peerConnection?.setRemoteDescription(
                  RTCSessionDescription(data['sdp'], 'answer'),
                );
              } else if (data['type'] == 'ice') {
                _peerConnection?.addCandidate(
                  RTCIceCandidate(
                    data['candidate'],
                    data['sdpMid'],
                    data['sdpMLineIndex'],
                  ),
                );
              } else if (data['type'] == 'delete_announcement') {
                deleteReceivedAnnouncement(data['id']);
              }
            } catch (e) {
              developer.log('Error processing received message: $e');
            }
          },
          onError: (e) {
            developer.log('Error in streamReceivedTexts: $e');
          },
        );

        p2p.streamClientList().listen(
          (clientList) {
            peers = clientList.where((c) => !c.isHost).toList();
            notifyListeners();
            for (var announcement in _createdAnnouncements) {
              _broadcastAnnouncement(announcement);
            }
          },
          onError: (e) {
            developer.log('Error in streamClientList: $e');
          },
        );

        _isInitialized = true;
        startNetworkMonitoring();
        _completer?.complete();
      } catch (e) {
        developer.log('Initialization error: $e');
        retries--;
        if (retries == 0) {
          _showErrorSnackBar(
            'Unable to activate Wi-Fi Direct. Please check Wi-Fi, Bluetooth, and tethering settings.',
            actionLabel: 'Open Tethering Settings',
            action: () => _channel.invokeMethod('openTetheringSettings'),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    _completer?.complete();
  }

  Future<void> createGroupWithRetry() async {
    try {
      await p2p.createGroup();
      _isServerStarted = true;
      developer.log('P2P group created successfully');
    } catch (e) {
      developer.log('Failed to create P2P group: $e');
      _isServerStarted = false;
      if (e.toString().contains('ERROR_TETHERING_DISALLOWED')) {
        _showErrorSnackBar(
          'Tethering is not allowed. Please enable it in Wi-Fi settings.',
          actionLabel: 'Open Tethering Settings',
          action: () => _channel.invokeMethod('openTetheringSettings'),
        );
      } else {
        _showErrorSnackBar(
          'Failed to create Wi-Fi Direct group. Please ensure Wi-Fi and Bluetooth are enabled.',
        );
      }
      throw e;
    }
  }

  Future<void> _ensureWifiAndBluetoothEnabled() async {
    try {
      await _channel.invokeMethod('enableWifi');
      await _channel.invokeMethod('enableBluetooth');
    } catch (e) {
      developer.log('Error enabling Wi-Fi/Bluetooth: $e');
      throw Exception('Failed to enable Wi-Fi/Bluetooth');
    }
  }

  void startNetworkMonitoring() {
    Timer.periodic(Duration(seconds: 10), (timer) async {
      if (!_isInitialized || !_isServerStarted) {
        developer.log('Network not initialized, retrying...');
        await initialize();
      }
      if (peers.isEmpty) {
        developer.log(
          'No peers connected, relying on streamClientList updates...',
        );
        // Peer discovery is handled by streamClientList, no explicit discoverPeers needed
      }
    });
  }

  Future<void> _retryInitialization(BuildContext context) async {
    final statuses = await [
      Permission.location,
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.notification,
      if (Platform.isAndroid &&
          (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33)
        Permission.nearbyWifiDevices,
    ].request();

    bool allPermissionsGranted = statuses.values.every(
      (status) => status.isGranted,
    );

    if (allPermissionsGranted && context.mounted) {
      developer.log('All permissions granted, retrying initialization');
      _isInitialized = false;
      _isServerStarted = false;
      _completer = Completer<void>();
      await initialize();
    } else if (context.mounted) {
      developer.log('Some permissions still missing after retry');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Some permissions are still missing.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _retryInitialization(context),
          ),
        ),
      );
    }
  }

  void addCreatedAnnouncement(Announcement announcement) {
    _createdAnnouncements.add(announcement);
    notifyListeners();
    _broadcastAnnouncement(announcement);
  }

  void updateCreatedAnnouncement(Announcement updatedAnnouncement) {
    final index = _createdAnnouncements.indexWhere(
      (ann) => ann.id == updatedAnnouncement.id,
    );
    if (index != -1) {
      _createdAnnouncements[index] = updatedAnnouncement;
      notifyListeners();
      _broadcastAnnouncement(updatedAnnouncement);
    }
  }

  void addReceivedAnnouncement(Announcement announcement) {
    _receivedAnnouncements.add(announcement);
    notifyListeners();
    if (_selectedCategories.contains(announcement.category)) {
      _showNotification(announcement);
    }
  }

  void deleteCreatedAnnouncement(String id) {
    _createdAnnouncements.removeWhere((ann) => ann.id == id);
    notifyListeners();
    _broadcastDeletion(id);
  }

  void deleteReceivedAnnouncement(String id) {
    _receivedAnnouncements.removeWhere((ann) => ann.id == id);
    notifyListeners();
  }

  void _broadcastAnnouncement(Announcement announcement) async {
    if (!_isInitialized || !_isServerStarted) {
      developer.log('P2P not initialized or server not started');
      return;
    }
    try {
      await p2p.broadcastText(jsonEncode(announcement.toJson()));
      developer.log('Announcement broadcasted');
    } catch (e) {
      developer.log('Broadcast error: $e');
      if (e.toString().contains('SELinux')) {
        developer.log('SELinux violation detected during broadcast');
      }
    }
  }

  void _broadcastDeletion(String id) async {
    if (!_isInitialized || !_isServerStarted) {
      return;
    }
    try {
      await p2p.broadcastText(
        jsonEncode({'type': 'delete_announcement', 'id': id}),
      );
    } catch (e) {
      developer.log('Deletion broadcast error: $e');
      if (e.toString().contains('SELinux')) {
        developer.log('SELinux violation detected during deletion');
      }
    }
  }

  void _showNotification(Announcement announcement) async {
    if (await Permission.notification.isGranted) {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidDetails = AndroidNotificationDetails(
        'channel_id',
        'Annonces',
        importance: Importance.max,
        priority: Priority.high,
        color: neonBlue,
      );
      const notificationDetails = NotificationDetails(android: androidDetails);
      await flutterLocalNotificationsPlugin.show(
        0,
        announcement.title,
        announcement.description,
        notificationDetails,
      );
    } else {
      developer.log('Notification permission not granted');
      _showErrorSnackBar(
        'Please grant notification permission to receive alerts.',
        actionLabel: 'Settings',
        action: () => openAppSettings(),
      );
    }
  }

  void _showErrorSnackBar(
    String message, {
    String actionLabel = 'Open Settings',
    VoidCallback? action,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: actionLabel,
              onPressed:
                  action ??
                  () async {
                    try {
                      await _channel.invokeMethod('openWifiSettings');
                    } catch (e) {
                      developer.log('Error opening Wi-Fi settings: $e');
                    }
                  },
            ),
          ),
        );
      }
    });
  }

  Future<void> initiateCall(String peerId, String deviceAddress) async {
    if (!(await Permission.microphone.request()).isGranted) {
      throw Exception('Microphone permission denied');
    }

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    _peerConnection = await createPeerConnection(configuration);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    _localStream!.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await p2p.broadcastText(
      jsonEncode({
        'type': 'offer',
        'sdp': offer.sdp,
        'from': deviceId,
        'to': peerId,
      }),
    );

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      p2p.broadcastText(
        jsonEncode({
          'type': 'ice',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'to': peerId,
        }),
      );
    };

    _peerConnection!.onTrack = (event) {};
  }

  Future<void> _handleOffer(String sdp, String from, String to) async {
    if (to != deviceId) return;

    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'offer'),
    );

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await p2p.broadcastText(
      jsonEncode({'type': 'answer', 'sdp': answer.sdp, 'to': from}),
    );

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      p2p.broadcastText(
        jsonEncode({
          'type': 'ice',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'to': from,
        }),
      );
    };
  }

  @override
  void dispose() {
    _localStream?.dispose();
    _peerConnection?.close();
    p2p.dispose();
    super.dispose();
  }
}

Future<Announcement> parseAnnouncement(Map<String, dynamic> json) async {
  return await compute(_parseAnnouncement, json);
}

Announcement _parseAnnouncement(Map<String, dynamic> json) {
  return Announcement(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    broadcasterId: json['broadcasterId'],
    broadcasterName: json['broadcasterName'],
    deviceAddress: json['deviceAddress'],
    imageBase64: json['imageBase64'],
    category: json['category'] ?? 'Autres',
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidInitSettings = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const initializationSettings = InitializationSettings(
    android: androidInitSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(
    ChangeNotifierProvider(
      create: (context) => AnnouncementProvider(),
      child: const XchangeApp(),
    ),
  );
}

class XchangeApp extends StatelessWidget {
  const XchangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xchange',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: neonBlue,
          secondary: neonPurple,
          surface: darkBackground,
        ),
        primaryColor: neonBlue,
        scaffoldBackgroundColor: darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkBackground,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: neonBlue,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: neonPurple,
          foregroundColor: Colors.white,
          elevation: 8,
          hoverColor: accentGlow,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          margin: EdgeInsets.all(12),
          color: Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: neonBlue),
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Montserrat'),
          bodyMedium: TextStyle(
            color: Colors.white70,
            fontFamily: 'Montserrat',
          ),
          titleLarge: TextStyle(
            color: neonBlue,
            fontWeight: FontWeight.bold,
            fontFamily: 'Montserrat',
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: neonPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      navigatorKey: navigatorKey,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('xchange', style: TextStyle(color: neonBlue)),
        backgroundColor: darkBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: neonBlue),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CategoryFilterScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [darkBackground, Color(0xFF141432)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: neonBlue.withValues()),
                ),
                child: TabBar(
                  labelColor: neonBlue,
                  unselectedLabelColor: Colors.white70,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: [neonBlue, neonPurple]),
                  ),
                  tabs: [
                    Tab(text: 'Reçues'),
                    Tab(text: 'Créées'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Consumer<AnnouncementProvider>(
                      builder: (context, provider, _) {
                        return ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: provider.receivedAnnouncements.length,
                          itemBuilder: (context, index) {
                            final announcement =
                                provider.receivedAnnouncements[index];
                            return TweetLikeCard(announcement: announcement);
                          },
                        );
                      },
                      child: const Center(
                        child: Text('No announcements received'),
                      ),
                    ),
                    Consumer<AnnouncementProvider>(
                      builder: (context, provider, _) {
                        return ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: provider.createdAnnouncements.length,
                          itemBuilder: (context, index) {
                            final announcement =
                                provider.createdAnnouncements[index];
                            return TweetLikeCard(
                              announcement: announcement,
                              isCreated: true,
                            );
                          },
                        );
                      },
                      child: const Center(
                        child: Text('No announcements created'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateAnnouncementScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
        elevation: 8,
      ),
    );
  }
}

class CategoryFilterScreen extends StatefulWidget {
  const CategoryFilterScreen({super.key});

  @override
  State<CategoryFilterScreen> createState() => _CategoryFilterScreenState();
}

class _CategoryFilterScreenState extends State<CategoryFilterScreen> {
  late Set<String> _tempSelectedCategories;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AnnouncementProvider>(context, listen: false);
    _tempSelectedCategories = Set.from(provider.selectedCategories);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Filtrer les catégories',
          style: TextStyle(color: neonBlue),
        ),
        backgroundColor: darkBackground,
        actions: [
          TextButton(
            onPressed: () {
              Provider.of<AnnouncementProvider>(
                context,
                listen: false,
              ).updateSelectedCategories(_tempSelectedCategories);
              Navigator.pop(context);
            },
            child: const Text('Appliquer', style: TextStyle(color: neonBlue)),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [darkBackground, Color(0xFF141432)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: AnnouncementProvider.categories.length,
          itemBuilder: (context, index) {
            final category = AnnouncementProvider.categories[index];
            return CheckboxListTile(
              title: Text(
                category,
                style: const TextStyle(color: Colors.white),
              ),
              value: _tempSelectedCategories.contains(category),
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    _tempSelectedCategories.add(category);
                  } else {
                    _tempSelectedCategories.remove(category);
                  }
                });
              },
              checkColor: Colors.white,
              activeColor: neonBlue,
            );
          },
        ),
      ),
    );
  }
}

class TweetLikeCard extends StatelessWidget {
  final Announcement announcement;
  final bool isCreated;

  const TweetLikeCard({
    super.key,
    required this.announcement,
    this.isCreated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF2A2A4E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: neonPurple,
                foregroundColor: Colors.white,
                radius: 24,
                child: Text(
                  announcement.broadcasterName[0],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          announcement.broadcasterName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '@${announcement.broadcasterId.substring(0, 8)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      announcement.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: neonBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      announcement.description,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Catégorie: ${announcement.category}',
                      style: const TextStyle(
                        color: neonPurple,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (announcement.imageBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ImageDetailScreen(
                                    imageBytes: announcement.imageBytes!,
                                  ),
                                ),
                              );
                            },
                            child: Image.memory(
                              announcement.imageBytes!,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isCreated)
                          IconButton(
                            tooltip: 'Call',
                            icon: const Icon(Icons.call, color: neonBlue),
                            onPressed: () async {
                              if (!context.mounted) return;
                              try {
                                await Provider.of<AnnouncementProvider>(
                                  context,
                                  listen: false,
                                ).initiateCall(
                                  announcement.broadcasterId,
                                  announcement.deviceAddress,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Call initiated'),
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            },
                          ),
                        if (isCreated)
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit, color: neonBlue),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      CreateAnnouncementScreen(
                                        announcement: announcement,
                                      ),
                                ),
                              );
                            },
                          ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            if (isCreated) {
                              Provider.of<AnnouncementProvider>(
                                context,
                                listen: false,
                              ).deleteCreatedAnnouncement(announcement.id);
                            } else {
                              Provider.of<AnnouncementProvider>(
                                context,
                                listen: false,
                              ).deleteReceivedAnnouncement(announcement.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ImageDetailScreen extends StatelessWidget {
  final Uint8List imageBytes;

  const ImageDetailScreen({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: darkBackground),
      backgroundColor: Colors.black,
      body: Center(child: Image.memory(imageBytes)),
    );
  }
}

class CreateAnnouncementScreen extends StatefulWidget {
  final Announcement? announcement;

  const CreateAnnouncementScreen({super.key, this.announcement});

  @override
  State<CreateAnnouncementScreen> createState() =>
      _CreateAnnouncementScreenState();
}

class _CreateAnnouncementScreenState extends State<CreateAnnouncementScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  String _selectedCategory = AnnouncementProvider.categories[0];

  @override
  void initState() {
    super.initState();
    if (widget.announcement != null) {
      _titleController.text = widget.announcement!.title;
      _descriptionController.text = widget.announcement!.description;
      _selectedCategory = widget.announcement!.category;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        _imageFile = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.announcement == null
              ? 'Create Announcement'
              : 'Edit Announcement',
          style: const TextStyle(color: neonBlue),
        ),
        backgroundColor: darkBackground,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [darkBackground, Color(0xFF141432)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: const TextStyle(color: neonBlue),
                    filled: true,
                    fillColor: Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withValues()),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withValues()),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: neonBlue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => FocusScope.of(
                    context,
                  ).requestFocus(_descriptionFocusNode),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: const TextStyle(color: neonBlue),
                    filled: true,
                    fillColor: Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withValues()),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withValues()),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: neonBlue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle: const TextStyle(color: neonBlue),
                    filled: true,
                    fillColor: Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withValues()),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withValues()),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: neonBlue),
                    ),
                  ),
                  dropdownColor: const Color(0xFF1A1A2E),
                  style: const TextStyle(color: Colors.white),
                  items: AnnouncementProvider.categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo, color: Colors.white),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neonPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      label: const Text('Camera'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neonPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_imageFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_imageFile!.path),
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                if (widget.announcement?.imageBase64 != null &&
                    _imageFile == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(widget.announcement!.imageBase64!),
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Consumer<AnnouncementProvider>(
                  builder: (context, provider, _) => ElevatedButton(
                    onPressed:
                        provider.isInitialized && provider.isServerStarted
                        ? () async {
                            if (!context.mounted) return;
                            FocusScope.of(context).unfocus();
                            final announcement = Announcement(
                              id: widget.announcement?.id ?? const Uuid().v4(),
                              title: _titleController.text,
                              description: _descriptionController.text,
                              broadcasterId: provider.deviceId,
                              broadcasterName: provider.deviceName,
                              deviceAddress: provider.peers.isNotEmpty
                                  ? provider.peers[0].id
                                  : '',
                              imageBase64: _imageFile != null
                                  ? base64Encode(
                                      await _imageFile!.readAsBytes(),
                                    )
                                  : widget.announcement?.imageBase64,
                              category: _selectedCategory,
                            );
                            if (widget.announcement == null) {
                              provider.addCreatedAnnouncement(announcement);
                            } else {
                              provider.updateCreatedAnnouncement(announcement);
                            }
                            Navigator.pop(context);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neonBlue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.announcement == null ? 'Publish' : 'Update',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }
}
