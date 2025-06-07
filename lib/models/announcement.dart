class Announcement {
  final String id;
  final String title;
  final String description;
  final double price;
  final String? imageBase64;
  final String? ip;
  final String? ssid;
  final String? psk;

  Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.imageBase64,
    this.ip,
    this.ssid,
    this.psk,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      imageBase64: json['imageBase64'] as String?,
      ip: json['ip'] as String?,
      ssid: json['ssid'] as String?,
      psk: json['psk'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'imageBase64': imageBase64,
        'ip': ip,
        'ssid': ssid,
        'psk': psk,
      };
}
