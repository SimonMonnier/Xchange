class Announcement {
  final String id;
  final String title;
  final String description;
  final double price;
  final String? imageUrl;
  final String? phone;
  final String? ip;

  Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.imageUrl,
    this.phone,
    this.ip,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String?,
      phone: json['phone'] as String?,
      ip: json['ip'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'phone': phone,
        'ip': ip,
      };
}
