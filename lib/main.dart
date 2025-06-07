import 'dart:async';
import 'package:flutter/material.dart';

import 'models/sale_ad.dart';
import 'nearby_ads_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final NearbyAdsService service = NearbyAdsService();

  @override
  void initState() {
    super.initState();
    // Service initializes itself in the constructor, but calling here
    // ensures permissions are requested as soon as the app starts.
    unawaited(service.initialize());
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearby Ads',
      home: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          return Home(service: service);
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
    switch (service.state) {
      case AdsState.idle:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AdsState.ready:
        return AdsPage(service: service);
    }
  }
}

class AdsPage extends StatefulWidget {
  final NearbyAdsService service;

  const AdsPage({super.key, required this.service});

  @override
  State<AdsPage> createState() => _AdsPageState();
}

class _AdsPageState extends State<AdsPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sale Ads')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
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
                ElevatedButton(
                  onPressed: () {
                    final ad = SaleAd(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: _titleController.text,
                      description: _descriptionController.text,
                      price: double.tryParse(_priceController.text) ?? 0,
                    );
                    widget.service.publishAd(ad);
                  },
                  child: const Text('Send Ad'),
                ),
              ],
            ),
          ),
          const Divider(),
          const Text('Received Ads'),
          Expanded(
            child: ListView(
              children: [
                ...widget.service.incomingAds.map(
                  (ad) => ListTile(
                    title: Text(ad.title),
                    subtitle: Text(ad.description),
                    // Display a dollar sign followed by the price.
                    trailing: Text('\$${ad.price.toStringAsFixed(2)}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

