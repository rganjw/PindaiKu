class NoteModel {
  final String id;
  final String title;
  final String subject;
  final String category;
  final String content;
  final DateTime createdAt;
  final String? imagePath;

  NoteModel({
    required this.id,
    required this.title,
    required this.subject,
    this.category = 'Catatan',
    required this.content,
    required this.createdAt,
    this.imagePath,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subject': subject,
      'category': category,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'imagePath': imagePath,
    };
  }

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      subject: json['subject'] ?? 'Umum / Lainnya',
      category: json['category'] ?? 'Catatan',
      content: json['content'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      imagePath: json['imagePath'],
    );
  }
}
