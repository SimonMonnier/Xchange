import 'package:flutter/material.dart';

import 'models/announcement.dart';
import 'nearby_ads_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final TextEditingController _imageController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _imageController.dispose();
    _phoneController.dispose();
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
              TextField(
                controller: _imageController,
                decoration: const InputDecoration(labelText: 'Image URL (optional)'),
              ),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                keyboardType: TextInputType.phone,
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
                      phone: _phoneController.text.trim().isEmpty
                          ? null
                          : _phoneController.text.trim(),
                    );
                    _titleController.clear();
                    _descriptionController.clear();
                    _priceController.clear();
                    _imageController.clear();
                    _phoneController.clear();
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
          leading: a.imageUrl != null
              ? Image.network(a.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
              : null,
          title: Text(a.title),
          subtitle: Text('${a.description}\nPrice: ${a.price}'),
          trailing: a.phone != null
              ? IconButton(
                  icon: const Icon(Icons.phone),
                  onPressed: () {
                    launchUrl(Uri.parse('tel:${a.phone}'));
                  },
                )
              : null,
        );
      }).toList(),
    );
  }
}
