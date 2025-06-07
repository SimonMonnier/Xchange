# Connexion Bluetooth avec photo et appel

Ce document explique comment étendre l'exemple d'annonces BLE afin de permettre
au téléphone qui reçoit une annonce de se connecter en Bluetooth à l'appareil
diffuseur. L'objectif est de récupérer l'image associée à l'annonce et de
proposer un bouton d'appel vers le diffuseur.

## 1. Serveur HTTP sur le diffuseur

En plus de diffuser l'identifiant et les informations principales via BLE,
l'appareil qui partage l'annonce lance un petit serveur HTTP local. Ce serveur
fonctionne aussi bien en Wi‑Fi standard qu'en Wi‑Fi Direct et renvoie le JSON
complet de l'annonce ainsi que l'image associée :

```dart
final server = await HttpServer.bind(InternetAddress.anyIPv4, 8081);
server.listen((req) async {
  if (req.uri.path == '/announcement') {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(ad.toJson()));
  } else if (req.uri.path == '/image' && ad.imageBase64 != null) {
    req.response.headers.contentType =
        ContentType('application', 'octet-stream');
    req.response.add(base64Decode(ad.imageBase64!));
  } else {
    req.response.statusCode = HttpStatus.notFound;
  }
  await req.response.close();
});
```

## 2. Connexion côté récepteur

Lorsqu'un appareil détecte une annonce grâce au paquet publicitaire, il peut se
connecter au groupe Wi‑Fi Direct indiqué dans l'annonce (SSID et clé
pré‑partagée). Une fois connecté, les détails complets sont récupérés via HTTP :

```dart
Future<Announcement?> fetchFullAd(Announcement ad) async {
  if (ad.ssid != null && ad.psk != null) {
    await p2pClient.connectWithCredentials(ad.ssid!, ad.psk!);
  }

  final resp = await http
      .get(Uri.parse('http://${ad.ip}:8081/announcement'))
      .timeout(const Duration(seconds: 5));

  if (resp.statusCode == 200) {
    return Announcement.fromJson(jsonDecode(resp.body));
  }
  return null;
}
```

Si `imageBase64` est présent dans la réponse, elle peut être affichée avec
`Image.memory(base64Decode(ad.imageBase64!))`.

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
téléphonique. Cette connexion peut également fonctionner en Wi‑Fi Direct : si un
groupe P2P est créé, le serveur écoute généralement sur l'adresse
`192.168.49.1`, ce qui permet un appel totalement hors connexion.
Dans l'application finale, le diffuseur crée automatiquement un groupe Wi‑Fi
Direct grâce au plugin `flutter_p2p_connection` et diffuse son SSID et sa clé
pré‑partagée dans l'annonce. En touchant le bouton **Appel Wi‑Fi**, le client se
connecte à ce groupe puis lance l'appel WebRTC.

---

Cette approche ajoute une étape de connexion BLE pour accéder aux informations
complètes et fonctionne hors connexion Internet lorsque les deux appareils sont à
proximité.
