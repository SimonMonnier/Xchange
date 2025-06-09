import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
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
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'broadcasterId': broadcasterId,
    'broadcasterName': broadcasterName,
    'deviceAddress': deviceAddress,
    'imageBase64': imageBase64,
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
  );
}

class AnnouncementProvider with ChangeNotifier {
  List<Announcement> _createdAnnouncements = [];
  List<Announcement> _receivedAnnouncements = [];
  String deviceId = Uuid().v4();
  String deviceName = 'Utilisateur';
  final FlutterP2pHost p2p = FlutterP2pHost();
  List<P2pClientInfo> peers = [];
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isInitialized = false;
  bool _isServerStarted = false;
  final Completer<void> _initCompleter = Completer<void>();

  Future<void> get initializationDone => _initCompleter.future;

  bool get isInitialized => _isInitialized;
  bool get isServerStarted => _isServerStarted;
  String? _downloadPath;
  static const MethodChannel _channel = MethodChannel('xchange/wifi_settings');

  List<Announcement> get createdAnnouncements => _createdAnnouncements;
  List<Announcement> get receivedAnnouncements => _receivedAnnouncements;

  AnnouncementProvider() {
    _init();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _downloadPath = directory.path;

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

    final statuses = await permissions.request();

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        print('Permission manquante: $permission');
      }
    });

    final hasNearbyPermission = sdkInt >= 33
        ? statuses[Permission.nearbyWifiDevices]!.isGranted
        : true;

    if (!statuses[Permission.location]!.isGranted ||
        !hasNearbyPermission ||
        !statuses[Permission.microphone]!.isGranted ||
        !statuses[Permission.bluetoothScan]!.isGranted ||
        !statuses[Permission.bluetoothConnect]!.isGranted ||
        !statuses[Permission.notification]!.isGranted) {
      print('Permissions nécessaires non accordées');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text(
              'Veuillez accorder toutes les permissions nécessaires.',
            ),
            action: SnackBarAction(
              label: 'Paramètres',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      });
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      return;
    }

    int retries = 3;
    while (retries > 0 && !_isInitialized) {
      print(
        'Tentative d\'initialisation Wi-Fi Direct, retries restants: $retries',
      );
      try {
        p2p.initialize();
        await p2p.createGroup();
        _isServerStarted = true;
        print('Groupe P2P créé');

        p2p.streamReceivedTexts().listen((message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'announcement') {
              final announcement = Announcement.fromJson(data);
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
            print('Erreur lors du traitement du message reçu : $e');
          }
        });

        p2p.streamClientList().listen((clientList) {
          peers = clientList.where((c) => !c.isHost).toList();
          notifyListeners();
          for (var announcement in _createdAnnouncements) {
            _broadcastAnnouncement(announcement);
          }
        });

        _isInitialized = true;
        if (!_initCompleter.isCompleted) {
          _initCompleter.complete();
        }
      } catch (e) {
        print('Erreur lors de l\'initialisation : $e');
        retries--;
        if (e.toString().contains('BLUETOOTH_DISABLED')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              const SnackBar(
                content: Text(
                  'Veuillez activer le Bluetooth pour utiliser le Wi-Fi Direct.',
                ),
              ),
            );
          });
        }
        if (retries == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              SnackBar(
                content: Text(
                  'Impossible d\'activer le Wi-Fi Direct. Veuillez vérifier les paramètres Wi-Fi.',
                ),
                action: SnackBarAction(
                  label: 'Ouvrir Paramètres Wi-Fi',
                  onPressed: () async {
                    try {
                      await _channel.invokeMethod('openWifiSettings');
                    } catch (e) {
                      print(
                        'Erreur lors de l\'ouverture des paramètres Wi-Fi : $e',
                      );
                    }
                  },
                ),
              ),
            );
          });
        }
        await Future.delayed(Duration(seconds: 2));
      }
    }
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
  }

  void addCreatedAnnouncement(Announcement announcement) {
    _createdAnnouncements.add(announcement);
    notifyListeners();
    _broadcastAnnouncement(announcement);
  }

  void addReceivedAnnouncement(Announcement announcement) {
    _receivedAnnouncements.add(announcement);
    notifyListeners();
    _showNotification(announcement);
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
      print('P2P non initialisé ou serveur non démarré');
      return;
    }
    try {
      await p2p.broadcastText(jsonEncode(announcement.toJson()));
      print('Annonce broadcastée');
    } catch (e) {
      print('Erreur lors de la diffusion : $e');
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
      print('Erreur lors de la diffusion de la suppression : $e');
    }
  }

  void _showNotification(Announcement announcement) async {
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
  }

  Future<void> initiateCall(String peerId, String deviceAddress) async {
    if (!(await Permission.microphone.request().isGranted)) {
      throw Exception('Permission microphone refusée');
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
      _peerConnection!.addTrack(track, _localStream!);
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

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        p2p.broadcastText(
          jsonEncode({
            'type': 'ice',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'to': peerId,
          }),
        );
      }
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

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        p2p.broadcastText(
          jsonEncode({
            'type': 'ice',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'to': from,
          }),
        );
      }
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
      child: XchangeApp(),
    ),
  );
}

class XchangeApp extends StatelessWidget {
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
        appBarTheme: AppBarTheme(
          backgroundColor: darkBackground,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: neonBlue,
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: neonPurple,
          foregroundColor: Colors.white,
          elevation: 8,
          hoverColor: accentGlow,
        ),
        cardTheme: CardTheme(
          elevation: 4,
          margin: EdgeInsets.all(12),
          color: Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: neonBlue.withOpacity(0.2)),
          ),
        ),
        textTheme: TextTheme(
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
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: TextStyle(
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
        title: Text('xchange', style: TextStyle(color: neonBlue)),
        backgroundColor: darkBackground,
      ),
      body: Container(
        decoration: BoxDecoration(
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
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: neonBlue.withOpacity(0.3)),
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
                      builder: (context, provider, child) {
                        return ListView.builder(
                          padding: EdgeInsets.all(8),
                          itemCount: provider.receivedAnnouncements.length,
                          itemBuilder: (context, index) {
                            final announcement =
                                provider.receivedAnnouncements[index];
                            return TweetLikeAnnouncement(
                              announcement: announcement,
                            );
                          },
                        );
                      },
                    ),
                    Consumer<AnnouncementProvider>(
                      builder: (context, provider, child) {
                        return ListView.builder(
                          padding: EdgeInsets.all(8),
                          itemCount: provider.createdAnnouncements.length,
                          itemBuilder: (context, index) {
                            final announcement =
                                provider.createdAnnouncements[index];
                            return TweetLikeAnnouncement(
                              announcement: announcement,
                              isCreated: true,
                            );
                          },
                        );
                      },
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
        child: Icon(Icons.add),
        elevation: 8,
      ),
    );
  }
}

class TweetLikeAnnouncement extends StatelessWidget {
  final Announcement announcement;
  final bool isCreated;

  const TweetLikeAnnouncement({
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
          gradient: LinearGradient(
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
                  style: TextStyle(fontWeight: FontWeight.bold),
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '@${announcement.broadcasterId.substring(0, 8)}',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      announcement.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: neonBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      announcement.description,
                      style: TextStyle(color: Colors.white70),
                    ),
                    if (announcement.imageBytes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GestureDetector(
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(announcement.imageBytes!),
                                ),
                              ),
                            ),
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
                            tooltip: 'Appeler',
                            icon: Icon(Icons.call, color: neonBlue),
                            onPressed: () async {
                              try {
                                await Provider.of<AnnouncementProvider>(
                                  context,
                                  listen: false,
                                ).initiateCall(
                                  announcement.broadcasterId,
                                  announcement.deviceAddress,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Appel initié')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erreur : $e')),
                                );
                              }
                            },
                          ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: Icon(
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

class CreateAnnouncementScreen extends StatefulWidget {
  const CreateAnnouncementScreen({super.key});

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
        title: Text('Créer une annonce', style: TextStyle(color: neonBlue)),
        backgroundColor: darkBackground,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [darkBackground, Color(0xFF141432)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                decoration: InputDecoration(
                  labelText: 'Titre',
                  labelStyle: TextStyle(color: neonBlue),
                  filled: true,
                  fillColor: Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: neonBlue.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: neonBlue.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: neonBlue),
                  ),
                ),
                style: TextStyle(color: Colors.white),
                onSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_descriptionFocusNode),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: neonBlue),
                  filled: true,
                  fillColor: Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: neonBlue.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: neonBlue.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: neonBlue),
                  ),
                ),
                style: TextStyle(color: Colors.white),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: Icon(Icons.photo, color: Colors.white),
                    label: Text('Galerie'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: neonPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: Icon(Icons.camera_alt, color: Colors.white),
                    label: Text('Camera'),
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
                  padding: const EdgeInsets.only(top: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_imageFile!.path),
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Consumer<AnnouncementProvider>(
                builder: (context, provider, _) => ElevatedButton(
                  onPressed: provider.isInitialized && provider.isServerStarted
                      ? () async {
                          FocusScope.of(context).unfocus();
                          final announcement = Announcement(
                            id: Uuid().v4(),
                            title: _titleController.text,
                            description: _descriptionController.text,
                            broadcasterId: provider.deviceId,
                            broadcasterName: provider.deviceName,
                            deviceAddress: provider.peers.isNotEmpty
                                ? provider.peers[0].id
                                : '',
                            imageBase64: _imageFile != null
                                ? base64Encode(await _imageFile!.readAsBytes())
                                : null,
                          );
                          provider.addCreatedAnnouncement(announcement);
                          Navigator.pop(context);
                        }
                      : null,
                  child: Text('Diffuser', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: neonBlue,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
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
