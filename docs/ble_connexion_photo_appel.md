# Connexion Bluetooth avec photo et appel

Ce document explique comment étendre l'exemple d'annonces BLE afin de permettre
au téléphone qui reçoit une annonce de se connecter en Bluetooth à l'appareil
diffuseur. L'objectif est de récupérer l'image associée à l'annonce et de
proposer un bouton d'appel vers le diffuseur.

## 1. Service GATT sur le diffuseur

En plus de la diffusion via `flutter_ble_peripheral`, l'appareil qui partage
l'annonce peut exposer un petit serveur BLE (service GATT) pour fournir des
informations détaillées.

1. Définissez un UUID de service personnalisé, par exemple
   `0000abcd-0000-1000-8000-00805f9b34fb`.
2. Créez deux caractéristiques :
   - **Annonce** (`0000abcd-0001-1000-8000-00805f9b34fb`) contenant le JSON
     complet de l'annonce (incluant `imageBase64` si l'image doit être
     transférée hors connexion).
   - **Image** (`0000abcd-0002-1000-8000-00805f9b34fb`) pour envoyer les octets
de l'image si elle est trop volumineuse pour être incluse dans le JSON.
3. Utilisez une bibliothèque comme `flutter_gatt_server` (Android uniquement) ou
   un plugin équivalent pour publier ce service.

```dart
final serviceUuid = Guid('0000abcd-0000-1000-8000-00805f9b34fb');
final adChar = Characteristic(
  uuid: Guid('0000abcd-0001-1000-8000-00805f9b34fb'),
  value: utf8.encode(jsonEncode(ad.toJson())),
);
final imageChar = Characteristic(
  uuid: Guid('0000abcd-0002-1000-8000-00805f9b34fb'),
  value: imageBytes,
);
GattServer().addService(BleService(serviceUuid, [adChar, imageChar]));
```

## 2. Connexion côté récepteur

Lorsqu'un appareil détecte une annonce grâce au paquet publicitaire, il peut se
connecter à l'annonceur avec `flutter_blue_plus` pour récupérer les données
supplémentaires :

```dart
Future<Announcement?> fetchFullAd(ScanResult result) async {
  final device = result.device;
  await device.connect();

  final services = await device.discoverServices();
  final service = services.firstWhere(
    (s) => s.serviceUuid.toString() ==
        '0000abcd-0000-1000-8000-00805f9b34fb',
  );

  final adData = await service
      .characteristics
      .firstWhere((c) =>
          c.uuid.toString() == '0000abcd-0001-1000-8000-00805f9b34fb')
      .read();

  final imgBytes = await service
      .characteristics
      .firstWhere((c) =>
          c.uuid.toString() == '0000abcd-0002-1000-8000-00805f9b34fb')
      .read();

  final map = jsonDecode(utf8.decode(adData));
  map['imageBase64'] = base64Encode(imgBytes);
  await device.disconnect();

  return Announcement.fromJson(map);
}
```

L'image est ensuite affichée avec `Image.memory` :

```dart
Image.memory(base64Decode(ad.imageBase64!));
```

## 3. Appeler le diffuseur

Une fois l'annonce complète récupérée, l'application initie un appel audio pair
à pair via Wi-Fi en utilisant WebRTC. Le diffuseur lance un petit serveur HTTP
local pour échanger l'offre et la réponse SDP :

```dart
await voipService.startServer(); // côté diffuseur

// côté récepteur
await voipService.call(ad.ip!);
```

La communication passe alors par le réseau local sans nécessiter le réseau
téléphonique.

---

Cette approche ajoute une étape de connexion BLE pour accéder aux informations
complètes et fonctionne hors connexion Internet lorsque les deux appareils sont à
proximité.
