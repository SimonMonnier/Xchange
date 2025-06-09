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

enum Role { host, client }

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
  Role? _role; // Rôle de l'appareil (hôte ou client)
  final Set<String> _connectedHosts =
      {}; // Liste des hôtes auxquels le client est connecté
  Completer<void>? _completer;
  Set<String> _selectedCategories = {'Autres'};
  static const MethodChannel _channel = MethodChannel('xchange/wifi_settings');

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
  Role? get role => _role;

  List<Announcement> get createdAnnouncements => _createdAnnouncements;
  List<Announcement> get receivedAnnouncements => _receivedAnnouncements
      .where((ann) => _selectedCategories.contains(ann.category))
      .toList();
  Set<String> get selectedCategories => _selectedCategories;

  void setRole(Role newRole) {
    _role = newRole;
    notifyListeners();
    initialize();
  }

  AnnouncementProvider();

  void updateSelectedCategories(Set<String> newCategories) {
    _selectedCategories = newCategories.isNotEmpty ? newCategories : {'Autres'};
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_role == null) {
      developer.log('Rôle non défini, initialisation annulée');
      return;
    }

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
      Permission.bluetoothAdvertise,
      Permission.notification,
    ];

    if (sdkInt >= 33) {
      permissions.add(Permission.nearbyWifiDevices);
    }

    final statuses = await permissions.request();
    bool allPermissionsGranted = statuses.values.every(
      (status) => status.isGranted,
    );

    if (!allPermissionsGranted) {
      developer.log(
        'Certaines permissions requises ne sont pas accordées: $statuses',
      );
      _showErrorSnackBar(
        'Veuillez accorder toutes les permissions nécessaires (localisation, microphone, Bluetooth, etc.).',
        actionLabel: 'Paramètres',
        action: () => openAppSettings(),
      );
      _completer?.complete();
      return;
    }

    try {
      final wifiResult = await _channel.invokeMethod('enableWifi');
      if (wifiResult != true) {
        developer.log('Wi-Fi non activé ou déconnexion échouée');
        _showErrorSnackBar(
          'Impossible d\'activer le Wi-Fi ou de déconnecter le réseau actuel. Veuillez désactiver le Wi-Fi manuellement et réessayer.',
          actionLabel: 'Ouvrir les paramètres Wi-Fi',
          action: () => _channel.invokeMethod('openWifiSettings'),
        );
        _completer?.complete();
        return;
      }
      await _ensureWifiAndBluetoothEnabled();
      final isTetheringEnabled = await _channel.invokeMethod(
        'isTetheringEnabled',
      );
      if (!(isTetheringEnabled as bool)) {
        developer.log('Le tethering est désactivé');
        _showErrorSnackBar(
          'Le tethering est désactivé. Veuillez l\'activer dans les paramètres Wi-Fi.',
          actionLabel: 'Ouvrir les paramètres de tethering',
          action: () => _channel.invokeMethod('openTetheringSettings'),
        );
        _completer?.complete();
        return;
      }
    } catch (e) {
      developer.log(
        'Erreur lors de l\'activation du Wi-Fi/Bluetooth/Tethering : $e',
      );
      _showErrorSnackBar(
        'Veuillez activer le Wi-Fi, le Bluetooth et le tethering dans les paramètres.',
        actionLabel: 'Ouvrir les paramètres Wi-Fi',
        action: () => _channel.invokeMethod('openWifiSettings'),
      );
      _completer?.complete();
      return;
    }

    int retries = 3;
    while (retries > 0 && !_isInitialized) {
      developer.log(
        'Tentative d\'initialisation pour rôle ${_role}, tentatives restantes : $retries',
      );
      try {
        p2p.initialize();
        if (_role == Role.host) {
          await createGroupWithRetry();
          _isServerStarted = true;
          developer.log('Groupe P2P créé avec succès (hôte)');
        } else {
          // Mode client : découvrir les hôtes et se connecter
          await discoverPeers();
          if (peers.isNotEmpty) {
            await joinGroup();
            _isServerStarted = true;
            developer.log('Connexion à un hôte réussie (client)');
          } else {
            developer.log('Aucun hôte détecté, nouvelle tentative');
            retries--;
            await Future.delayed(const Duration(seconds: 5));
            continue;
          }
        }

        p2p.streamReceivedTexts().listen(
          (message) async {
            try {
              final data = await compute(jsonDecode, message);
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
              developer.log('Erreur lors du traitement du message reçu : $e');
            }
          },
          onError: (e) {
            developer.log('Erreur dans streamReceivedTexts : $e');
          },
        );

        p2p.streamClientList().listen(
          (clientList) {
            peers = clientList.where((c) => !c.isHost).toList();
            developer.log(
              'Pairs découverts: ${peers.map((p) => p.id).toList()}',
            );
            notifyListeners();
            if (_role == Role.host) {
              for (var announcement in _createdAnnouncements) {
                _broadcastAnnouncement(announcement);
              }
            }
          },
          onError: (e) {
            developer.log('Erreur dans streamClientList : $e');
          },
        );

        _isInitialized = true;
        startNetworkMonitoring();
        _completer?.complete();
      } catch (e) {
        developer.log('Erreur d\'initialisation : $e');
        retries--;
        if (retries == 0) {
          _showErrorSnackBar(
            'Impossible d\'initialiser le réseau. Veuillez vérifier les paramètres Wi-Fi, Bluetooth et tethering.',
            actionLabel: 'Ouvrir les paramètres de tethering',
            action: () => _channel.invokeMethod('openTetheringSettings'),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    _completer?.complete();
  }

  Future<void> discoverPeers() async {
    try {
      developer.log('Lancement de la découverte des pairs Wi-Fi Direct');
      final peersList = await _channel.invokeMethod('discoverPeers');
      developer.log('Pairs découverts via méthode native: $peersList');
      if (peersList is List && peersList.isNotEmpty) {
        peers = peersList
            .where((peer) => peer['isGroupOwner'] == true) // Filtrer les hôtes
            .map(
              (peer) => P2pClientInfo(
                id: peer['deviceAddress'],
                username: peer['deviceName'],
                isHost: peer['isGroupOwner'],
              ),
            )
            .toList();
        notifyListeners();

        // En mode client, tenter de se connecter à chaque nouvel hôte
        if (_role == Role.client) {
          for (var peer in peers) {
            if (!_connectedHosts.contains(peer.id)) {
              await joinWifiP2pGroup(peer.id);
              _connectedHosts.add(peer.id);
              developer.log('Connecté au hôte ${peer.id}');
            }
          }
        }
      }
    } catch (e) {
      developer.log('Erreur lors de la découverte des pairs : $e');
      _showErrorSnackBar(
        'Échec de la découverte des appareils. Veuillez vérifier les paramètres Wi-Fi.',
        actionLabel: 'Ouvrir les paramètres Wi-Fi',
        action: () => _channel.invokeMethod('openWifiSettings'),
      );
    }
  }

  Future<void> joinWifiP2pGroup(String deviceAddress) async {
    try {
      developer.log(
        'Tentative de connexion au groupe Wi-Fi Direct de $deviceAddress',
      );
      final success = await _channel.invokeMethod('joinWifiP2pGroup', {
        'deviceAddress': deviceAddress,
      });
      if (success == true) {
        developer.log('Connexion au groupe $deviceAddress réussie');
      } else {
        throw Exception('Échec de la connexion au groupe');
      }
    } catch (e) {
      developer.log(
        'Erreur lors de la connexion au groupe $deviceAddress : $e',
      );
      _showErrorSnackBar(
        'Impossible de se connecter au groupe Wi-Fi Direct. Veuillez réessayer.',
        actionLabel: 'Réessayer',
        action: () => joinWifiP2pGroup(deviceAddress),
      );
    }
  }

  Future<void> joinGroup() async {
    try {
      developer.log('Attente de connexion au groupe Wi-Fi Direct');
      await Future.delayed(Duration(seconds: 5)); // Attendre la connexion
      if (peers.isEmpty) {
        throw Exception(
          'Aucun pair connecté après tentative de rejoindre le groupe',
        );
      }
      developer.log('Connexion au groupe réussie');
    } catch (e) {
      developer.log('Échec de la connexion au groupe : $e');
      _showErrorSnackBar(
        'Impossible de rejoindre un groupe Wi-Fi Direct. Veuillez réessayer.',
        actionLabel: 'Réessayer',
        action: () => initialize(),
      );
    }
  }

  Future<void> createGroupWithRetry() async {
    int pluginRetries = 3;
    while (pluginRetries > 0 && !_isServerStarted) {
      try {
        developer.log(
          'Tentative de création de groupe avec flutter_p2p_connection, retries restants: $pluginRetries',
        );
        await p2p.createGroup();
        _isServerStarted = true;
        developer.log('Groupe P2P créé avec succès via flutter_p2p_connection');
        return;
      } catch (e) {
        developer.log('Échec avec flutter_p2p_connection: $e');
        pluginRetries--;
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    try {
      developer.log(
        'Tentative de création de groupe avec WifiP2pManager natif',
      );
      final success = await _channel.invokeMethod('createWifiP2pGroup');
      if (success == true) {
        _isServerStarted = true;
        developer.log('Groupe P2P créé avec succès via WifiP2pManager natif');
      } else {
        throw Exception('Échec de la création du groupe P2P natif');
      }
    } catch (nativeError) {
      developer.log('Échec avec WifiP2pManager natif: $nativeError');
      _isServerStarted = false;
      if (nativeError.toString().contains('WIFI_P2P_ERROR') ||
          nativeError.toString().contains('ERROR_TETHERING_DISALLOWED')) {
        _showErrorSnackBar(
          'Le tethering n\'est pas autorisé. Veuillez l\'activer dans les paramètres Wi-Fi.',
          actionLabel: 'Ouvrir les paramètres de tethering',
          action: () => _channel.invokeMethod('openTetheringSettings'),
        );
      } else {
        _showErrorSnackBar(
          'Échec de la création du groupe Wi-Fi Direct. Veuillez vérifier les paramètres Wi-Fi et Bluetooth.',
          actionLabel: 'Ouvrir les paramètres Wi-Fi',
          action: () => _channel.invokeMethod('openWifiSettings'),
        );
      }
      throw nativeError;
    }
  }

  Future<void> _ensureWifiAndBluetoothEnabled() async {
    try {
      final wifiResult = await _channel.invokeMethod('enableWifi');
      if (wifiResult != true) {
        throw Exception('Échec de l\'activation du Wi-Fi : $wifiResult');
      }
      developer.log('Wi-Fi activé avec succès');

      final bluetoothResult = await _channel.invokeMethod('enableBluetooth');
      if (bluetoothResult != true) {
        throw Exception(
          'Échec de l\'activation du Bluetooth : $bluetoothResult',
        );
      }
      developer.log('Bluetooth activé avec succès');
    } catch (e) {
      developer.log('Erreur lors de l\'activation du Wi-Fi/Bluetooth : $e');
      if (e.toString().contains('WIFI_ENABLE_FAILED') ||
          e.toString().contains('WIFI_SECURITY_ERROR')) {
        _showErrorSnackBar(
          'Impossible d\'activer le Wi-Fi automatiquement. Veuillez l\'activer manuellement dans les paramètres.',
          actionLabel: 'Ouvrir les paramètres Wi-Fi',
          action: () => _channel.invokeMethod('openWifiSettings'),
        );
      } else if (e.toString().contains('BLUETOOTH_ENABLE_FAILED')) {
        _showErrorSnackBar(
          'Impossible d\'activer le Bluetooth automatiquement. Veuillez l\'activer manuellement dans les paramètres.',
          actionLabel: 'Ouvrir les paramètres Bluetooth',
          action: () => _channel.invokeMethod('openBluetoothSettings'),
        );
      }
      throw e;
    }
  }

  void startNetworkMonitoring() {
    Timer.periodic(Duration(seconds: 10), (timer) async {
      if (!_isInitialized || !_isServerStarted) {
        developer.log('Réseau non initialisé, nouvelle tentative...');
        await initialize();
      } else if (_role == Role.client) {
        developer.log('Vérification des hôtes: ${peers.length} hôtes détectés');
        await discoverPeers();
        if (peers.isEmpty) {
          _showErrorSnackBar(
            'Aucun hôte détecté. Assurez-vous qu\'un appareil diffuse des annonces.',
            actionLabel: 'Réessayer',
            action: () => initialize(),
          );
        }
      } else {
        developer.log(
          'Vérification des clients: ${peers.length} clients détectés',
        );
        if (peers.isEmpty) {
          _showErrorSnackBar(
            'Aucun client détecté. Assurez-vous qu\'un appareil est configuré pour recevoir des annonces.',
            actionLabel: 'Réessayer',
            action: () => initialize(),
          );
        }
      }
    });
  }

  void _showErrorSnackBar(
    String message, {
    String actionLabel = 'Ouvrir les paramètres',
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
                      developer.log(
                        'Erreur lors de l\'ouverture des paramètres Wi-Fi : $e',
                      );
                    }
                  },
            ),
          ),
        );
      }
    });
  }

  Future<void> _retryInitialization(BuildContext context) async {
    final statuses = await [
      Permission.location,
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
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
      _showErrorSnackBar(
        'Certaines permissions sont toujours manquantes.',
        actionLabel: 'Réessayer',
        action: () => _retryInitialization(context),
      );
    }
  }

  void addCreatedAnnouncement(Announcement announcement) {
    if (_role != Role.host) {
      developer.log('Impossible de créer une annonce en mode client');
      _showErrorSnackBar('Seuls les hôtes peuvent diffuser des annonces.');
      return;
    }
    _createdAnnouncements.add(announcement);
    notifyListeners();
    _broadcastAnnouncement(announcement);
  }

  void updateCreatedAnnouncement(Announcement updatedAnnouncement) {
    if (_role != Role.host) {
      developer.log('Impossible de modifier une annonce en mode client');
      _showErrorSnackBar('Seuls les hôtes peuvent modifier des annonces.');
      return;
    }
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
    if (_role != Role.host) {
      developer.log('Impossible de supprimer une annonce en mode client');
      _showErrorSnackBar('Seuls les hôtes peuvent supprimer des annonces.');
      return;
    }
    _createdAnnouncements.removeWhere((ann) => ann.id == id);
    notifyListeners();
    _broadcastDeletion(id);
  }

  void deleteReceivedAnnouncement(String id) {
    _receivedAnnouncements.removeWhere((ann) => ann.id == id);
    notifyListeners();
  }

  void _broadcastAnnouncement(Announcement announcement) async {
    if (!_isInitialized || !_isServerStarted || _role != Role.host) {
      developer.log(
        'Diffusion annulée: non initialisé, serveur non démarré ou mode client',
      );
      return;
    }
    if (peers.isEmpty) {
      developer.log('Aucun client détecté pour diffuser l\'annonce');
      _showErrorSnackBar(
        'Aucun client connecté détecté. Assurez-vous qu\'un appareil est configuré pour recevoir des annonces.',
        actionLabel: 'Réessayer',
        action: () => initialize(),
      );
      return;
    }
    try {
      await p2p.broadcastText(jsonEncode(announcement.toJson()));
      developer.log('Annonce diffusée avec succès à ${peers.length} clients');
    } catch (e) {
      developer.log('Erreur de diffusion : $e');
      if (e.toString().contains('SELinux')) {
        developer.log('Violation SELinux détectée lors de la diffusion');
      }
      _showErrorSnackBar(
        'Échec de la diffusion de l\'annonce: $e',
        actionLabel: 'Réessayer',
        action: () => _broadcastAnnouncement(announcement),
      );
    }
  }

  void _broadcastDeletion(String id) async {
    if (!_isInitialized || !_isServerStarted || _role != Role.host) {
      return;
    }
    try {
      await p2p.broadcastText(
        jsonEncode({'type': 'delete_announcement', 'id': id}),
      );
      developer.log('Suppression diffusée avec succès');
    } catch (e) {
      developer.log('Erreur de diffusion de suppression : $e');
      if (e.toString().contains('SELinux')) {
        developer.log('Violation SELinux détectée lors de la suppression');
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
      developer.log('Permission de notification non accordée');
      _showErrorSnackBar(
        'Veuillez autoriser les notifications pour recevoir des alertes.',
        actionLabel: 'Paramètres',
        action: () => openAppSettings(),
      );
    }
  }

  Future<void> initiateCall(String peerId, String deviceAddress) async {
    if (!(await Permission.microphone.request()).isGranted) {
      throw Exception('Permission de microphone refusée');
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
          margin: const EdgeInsets.all(12),
          color: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: neonBlue),
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
      home: const RoleSelectionScreen(),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBackground,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [darkBackground, Color(0xFF141432)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Choisissez votre rôle',
                style: TextStyle(
                  color: neonBlue,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Provider.of<AnnouncementProvider>(
                    context,
                    listen: false,
                  ).setRole(Role.host);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: neonPurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Hôte (Diffuser des annonces)',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Provider.of<AnnouncementProvider>(
                    context,
                    listen: false,
                  ).setRole(Role.client);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: neonBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Client (Recevoir des annonces)',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AnnouncementProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          provider.role == Role.host ? 'xchange (Hôte)' : 'xchange (Client)',
          style: const TextStyle(color: neonBlue),
        ),
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
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: neonBlue.withOpacity(0.5)),
                ),
                child: TabBar(
                  labelColor: neonBlue,
                  unselectedLabelColor: Colors.white70,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [neonBlue, neonPurple],
                    ),
                  ),
                  tabs: const [
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
                      child: const Center(child: Text('Aucune annonce reçue')),
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
                      child: const Center(child: Text('Aucune annonce créée')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: provider.role == Role.host
          ? FloatingActionButton(
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
            )
          : null,
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
                            tooltip: 'Appeler',
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
                                  const SnackBar(content: Text('Appel initié')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erreur : $e')),
                                );
                              }
                            },
                          ),
                        if (isCreated)
                          IconButton(
                            tooltip: 'Modifier',
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
                          tooltip: 'Supprimer',
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
    } else {
      _titleController.text = ' '; // Valeur non vide par défaut
      _descriptionController.text = ' ';
    }

    // Éviter les erreurs de span vide
    _titleController.addListener(() {
      if (_titleController.text.isEmpty) {
        _titleController.text = ' ';
        _titleController.selection = TextSelection.collapsed(offset: 1);
      }
    });

    _descriptionController.addListener(() {
      if (_descriptionController.text.isEmpty) {
        _descriptionController.text = ' ';
        _descriptionController.selection = TextSelection.collapsed(offset: 1);
      }
    });
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
              ? 'Créer une annonce'
              : 'Modifier l\'annonce',
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
                    labelText: 'Titre',
                    labelStyle: const TextStyle(color: neonBlue),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withOpacity(0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withOpacity(0.5)),
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
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withOpacity(0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withOpacity(0.5)),
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
                    labelText: 'Catégorie',
                    labelStyle: const TextStyle(color: neonBlue),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withOpacity(0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: neonBlue.withOpacity(0.5)),
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
                      label: const Text('Galerie'),
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
                      label: const Text('Caméra'),
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
                            final title = _titleController.text.trim();
                            final description = _descriptionController.text
                                .trim();
                            if (title.isEmpty || description.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Le titre et la description ne peuvent pas être vides',
                                  ),
                                ),
                              );
                              return;
                            }
                            final announcement = Announcement(
                              id: widget.announcement?.id ?? const Uuid().v4(),
                              title: title,
                              description: description,
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
                      widget.announcement == null
                          ? 'Diffuser'
                          : 'Mettre à jour',
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
