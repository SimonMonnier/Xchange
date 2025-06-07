class SaleAd {
  final String id;
  final String title;
  final String description;
  final double price;

  SaleAd({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  factory SaleAd.fromJson(Map<String, dynamic> json) {
    return SaleAd(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
    };
  }
}
