import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'wifi_aware.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

import 'dart:convert';

import 'models/announcement.dart';
import 'nearby_ads_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final NearbyAdsService _service = NearbyAdsService();

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Announcements',
      home: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          switch (_service.state) {
            case AdsState.ready:
              return Home(service: _service);
            case AdsState.permissionDenied:
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Permissions Bluetooth requises.\nVeuillez les activer dans les paramètres.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: openAppSettings,
                        child: const Text('Ouvrir les paramètres'),
                      )
                    ],
                  ),
                ),
              );
            case AdsState.idle:
            default:
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
          }
        },
      ),
    );
  }
}

class Home extends StatelessWidget {
  final NearbyAdsService service;
  const Home({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BLE Announcements'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Ads'),
              Tab(text: 'Received'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MyAdsPage(service: service),
            ReceivedPage(service: service),
          ],
        ),
      ),
    );
  }
}

class MyAdsPage extends StatefulWidget {
  final NearbyAdsService service;
  const MyAdsPage({super.key, required this.service});
=======
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Aware Demo',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyAdsPage> createState() => _MyAdsPageState();
}

class _MyAdsPageState extends State<MyAdsPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _imageController = TextEditingController();
  String? _imageBase64;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _imageBase64 = base64Encode(bytes);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _imageController.dispose();
    super.dispose();
=======
class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    _notificationsPlugin.initialize(initializationSettings);
    WifiAware.messages.listen(_showNotification);
  }

  Future<void> _showNotification(String message) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails('wifi_aware', 'WiFi Aware'),
    );
    await _notificationsPlugin.show(0, 'Received message', message, details);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.service.selected;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: widget.service.announcements
                .map(
                  (a) => ListTile(
                    title: Text(a.title),
                    subtitle: Text('${a.description}\nPrice: ${a.price}'),
                    leading: Radio<Announcement>(
                      value: a,
                      groupValue: selected,
                      onChanged: (val) {
                        widget.service.selectAnnouncement(val);
                      },
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        widget.service.removeAnnouncement(a);
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _imageController,
                decoration: const InputDecoration(labelText: 'Image URL (optional)'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _pickImage,
                    child: const Text('Select Image'),
                  ),
                  if (_imageBase64 != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Image.memory(
                        base64Decode(_imageBase64!),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  final title = _titleController.text.trim();
                  final description = _descriptionController.text.trim();
                  final priceText = _priceController.text.trim();
                  if (title.isNotEmpty && description.isNotEmpty && priceText.isNotEmpty) {
                    final price = double.tryParse(priceText) ?? 0;
                    widget.service.addAnnouncement(
                      title: title,
                      description: description,
                      price: price,
                      imageUrl: _imageController.text.trim().isEmpty
                          ? null
                          : _imageController.text.trim(),
                      imageBase64: _imageBase64,
                    );
                    _titleController.clear();
                    _descriptionController.clear();
                    _priceController.clear();
                    _imageController.clear();
                    setState(() {
                      _imageBase64 = null;
                    });
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReceivedPage extends StatelessWidget {
  final NearbyAdsService service;
  const ReceivedPage({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: service.receivedAnnouncements.map((a) {
        return ListTile(
          leading: a.imageBase64 != null
              ? Image.memory(
                  base64Decode(a.imageBase64!),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                )
              : a.imageUrl != null
                  ? Image.network(a.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
                  : null,
          title: Text(a.title),
          subtitle: Text('${a.description}\nPrice: ${a.price}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              service.removeReceivedAnnouncement(a);
            },
          ),
        );
      }).toList(),
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi Aware Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Message to publish'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => WifiAware.startPublishing(_controller.text),
                  child: const Text('Publish'),
                ),
                ElevatedButton(
                  onPressed: WifiAware.startSubscribing,
                  child: const Text('Subscribe'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
