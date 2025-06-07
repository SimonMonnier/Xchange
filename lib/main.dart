import 'package:flutter/material.dart';

import 'models/announcement.dart';
import 'nearby_ads_service.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
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
                    title: Text(a.text),
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration:
                      const InputDecoration(labelText: 'New announcement'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isNotEmpty) {
                    widget.service.addAnnouncement(text);
                    _controller.clear();
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
      children: service.receivedAnnouncements
          .map((e) => ListTile(title: Text(e)))
          .toList(),
    );
  }
}
