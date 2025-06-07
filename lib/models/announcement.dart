class Announcement {
  final String id;
  final String title;
  final String description;
  final double price;
  final String? imageUrl;
  final String? imageBase64;
  final String? phone;

  Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.imageUrl,
    this.imageBase64,
    this.phone,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String?,
      imageBase64: json['imageBase64'] as String?,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'imageBase64': imageBase64,
        'phone': phone,
      };
}
