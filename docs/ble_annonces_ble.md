# Guide d'implémentation : Annonces BLE dans Flutter

Ce document explique comment développer une application Flutter capable de diffuser et recevoir des annonces de vente via Bluetooth Low Energy (BLE) sans connexion. Il suit les grandes étapes de la tâche utilisateur.

## 1. Création du projet
1. Créez un projet Flutter : `flutter create xchange`.
2. Ajoutez les dépendances dans `pubspec.yaml` :
   ```yaml
   dependencies:
     flutter_blue_plus: ^1.0.0
     flutter_ble_peripheral: ^1.0.0
     shared_preferences: ^2.0.0
   ```

## 2. Permissions
### Android
Ajoutez les permissions nécessaires dans `android/app/src/main/AndroidManifest.xml` :
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

### iOS
Ajoutez les clés dans `ios/Runner/Info.plist` :
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Permission requise pour scanner et diffuser via Bluetooth</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Permission de localisation requise pour détecter les appareils Bluetooth</string>
```

## 3. Modèle d'annonce
Créez une classe simple pour représenter une annonce :
```dart
class Announcement {
  final String id;
  final String title;
  final String description;
  final double price;
  final String? imageUrl;
  final String? imageBase64;

  Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.imageUrl,
    this.imageBase64,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'imageBase64': imageBase64,
      };

  static Announcement fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        price: (json['price'] as num).toDouble(),
        imageUrl: json['imageUrl'],
        imageBase64: json['imageBase64'],
      );
}
```

Stockez les annonces via `shared_preferences` :
```dart
Future<void> saveAnnouncements(List<Announcement> ads) async {
  final prefs = await SharedPreferences.getInstance();
  final json = jsonEncode(ads.map((a) => a.toJson()).toList());
  await prefs.setString('announcements', json);
}

Future<List<Announcement>> loadAnnouncements() async {
  final prefs = await SharedPreferences.getInstance();
  final json = prefs.getString('announcements');
  if (json == null) return [];
  final List data = jsonDecode(json);
  return data.map((e) => Announcement.fromJson(e)).toList();
}
```

## 4. Diffusion BLE
Utilisez `flutter_ble_peripheral` pour diffuser le JSON décrivant l'annonce dans les données fabricant :
```dart
void startAdvertising(Announcement ad) async {
  final jsonStr = jsonEncode(ad.toJson());
  final bytes = [0xFF, 0xFF, ...utf8.encode(jsonStr)];
  await FlutterBlePeripheral().startAdvertising(
    manufacturerData: Uint8List.fromList(bytes),
  );
}

void stopAdvertising() async {
  await FlutterBlePeripheral().stopAdvertising();
}
```

## 5. Scan BLE périodique
Scannez toutes les minutes pendant 10 secondes :
```dart
class BluetoothService {
  Timer? _timer;
  final List<String> received = [];

  void startScanning() {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _scan());
    _scan();
  }

  void _scan() async {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.manufacturerData.containsKey(0xFFFF)) {
          final bytes = r.advertisementData.manufacturerData[0xFFFF]!;
          final jsonStr = utf8.decode(bytes);
          final ad = Announcement.fromJson(jsonDecode(jsonStr));
          if (!received.any((a) => a.id == ad.id)) received.add(ad);
        }
      }
    });
  }

  void stopScanning() {
    _timer?.cancel();
    FlutterBluePlus.stopScan();
  }
}
```

## 6. Interface utilisateur
Prévoyez deux onglets :
1. **Gestion des annonces** pour ajouter, modifier, supprimer et choisir l'annonce à diffuser (titre, description, prix et image).
2. **Annonces reçues** affichant les informations complètes.

## 7. Contrôle de l'état Bluetooth
Vérifiez que Bluetooth est activé et demandez les permissions au démarrage :
```dart
Future<void> checkBluetooth() async {
  if (!await FlutterBluePlus.isEnabled) {
    await FlutterBluePlus.turnOn();
  }
  final perms = [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];
  final info = await DeviceInfoPlugin().androidInfo;
  if (info.version.sdkInt <= 30) {
    perms.add(Permission.locationWhenInUse);
  }
  await perms.request();
}
```

---

Ce guide résume l'implémentation d'une application Flutter inspirée de Wi-Fi Aware mais utilisant BLE pour échanger des annonces sans connexion.
