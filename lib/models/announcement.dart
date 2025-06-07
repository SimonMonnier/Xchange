class Announcement {
  final String id;
  final String title;
  final String description;
  final double price;
  final String? imageUrl;
  final String? imageBase64;
  final String? serverUrl;
  Announcement({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.imageUrl,
    this.imageBase64,
    this.serverUrl,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String?,
      imageBase64: json['imageBase64'] as String?,
      serverUrl: json['serverUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'imageBase64': imageBase64,
        'serverUrl': serverUrl,
      };

  Map<String, dynamic> toAdvertiseJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'serverUrl': serverUrl,
      };

  Announcement copyWith({
    String? id,
    String? title,
    String? description,
    double? price,
    String? imageUrl,
    String? imageBase64,
    String? serverUrl,
  }) {
    return Announcement(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      imageBase64: imageBase64 ?? this.imageBase64,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }
}
