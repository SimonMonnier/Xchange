class Announcement {
  final String id;
  final String text;

  Announcement({required this.id, required this.text});

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(id: json['id'] as String, text: json['text'] as String);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
      };
}
