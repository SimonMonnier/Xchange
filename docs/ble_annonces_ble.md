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
  final String text;

  Announcement({required this.id, required this.text});

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
  static Announcement fromJson(Map<String, dynamic> json) =>
      Announcement(id: json['id'], text: json['text']);
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
Utilisez `flutter_ble_peripheral` pour diffuser le texte dans les données fabricant :
```dart
void startAdvertising(String text) async {
  final bytes = [0xFF, 0xFF, ...utf8.encode(text)];
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
          final text = utf8.decode(bytes);
          if (!received.contains(text)) received.add(text);
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
1. **Gestion des annonces** pour ajouter, modifier, supprimer et choisir l'annonce à diffuser.
2. **Annonces reçues** affichant les textes détectés.

## 7. Contrôle de l'état Bluetooth
Vérifiez que Bluetooth est activé et demandez les permissions au démarrage :
```dart
Future<void> checkBluetooth() async {
  if (!await FlutterBluePlus.isEnabled) {
    await FlutterBluePlus.turnOn();
  }
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}
```

---

Ce guide résume l'implémentation d'une application Flutter inspirée de Wi-Fi Aware mais utilisant BLE pour échanger des annonces sans connexion.
