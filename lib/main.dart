import 'package:flutter/material.dart';

import 'models/announcement.dart';
import 'nearby_ads_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:typed_data';
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

  @override
  State<MyAdsPage> createState() => _MyAdsPageState();
}

class _MyAdsPageState extends State<MyAdsPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
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
              if (_imageBytes != null)
                Image.memory(_imageBytes!, width: 100, height: 100),
              ElevatedButton(
                onPressed: () async {
                  final picker = ImagePicker();
                  final file =
                      await picker.pickImage(source: ImageSource.gallery);
                  if (file != null) {
                    _imageBytes = await file.readAsBytes();
                    setState(() {});
                  }
                },
                child: const Text('Choose Image'),
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
                      imageBytes: _imageBytes,
                    );
                    _titleController.clear();
                    _descriptionController.clear();
                    _priceController.clear();
                    _imageBytes = null;
                    setState(() {});
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
              ? Image.memory(base64Decode(a.imageBase64!),
                  width: 56, height: 56, fit: BoxFit.cover)
              : null,
          title: Text(a.title),
          subtitle: Text('${a.description}\nPrice: ${a.price}'),
          onTap: () async {
            final full = await service.fetchFullAnnouncement(a.id);
            if (full == null) return;
            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text(full.title),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (full.imageBase64 != null)
                        Image.memory(base64Decode(full.imageBase64!)),
                      Text(full.description),
                      Text('Price: ${full.price}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer'),
                    ),
                    if (full.ip != null && full.ssid != null && full.psk != null)
                      TextButton(
                        onPressed: () {
                          service.callAnnouncement(full);
                        },
                        child: const Text('Appel Wi-Fi'),
                      ),
                  ],
                );
              },
            );
          },
        );
      }).toList(),
    );
  }
}
