class NoteModel {
  final String id;
  final String title;
  final String subject;
  final String category;
  final String content;
  final DateTime createdAt;
  final String? imagePath;

  /// Indeks pencarian huruf kecil yang dihitung malas (lazy) hanya satu kali
  /// per catatan agar filter pencarian tidak mengalokasikan String baru di tiap loop.
  late final String searchIndex =
      '${title.toLowerCase()}\n${subject.toLowerCase()}\n${content.toLowerCase()}';

  NoteModel({
    required this.id,
    required this.title,
    required this.subject,
    this.category = 'Catatan',
    required this.content,
    required this.createdAt,
    this.imagePath,
  });

  NoteModel copyWith({
    String? id,
    String? title,
    String? subject,
    String? category,
    String? content,
    DateTime? createdAt,
    String? imagePath,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      category: category ?? this.category,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'subject': subject,
      'category': category,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'imagePath': imagePath,
    };
  }

  factory NoteModel.fromJson(Map<String, Object?> json) {
    final Object? rawDate = json['createdAt'];
    final DateTime? parsedDate =
        rawDate is String ? DateTime.tryParse(rawDate) : null;

    return NoteModel(
      id: json['id'] is String ? json['id'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      subject: json['subject'] is String
          ? json['subject'] as String
          : 'Umum / Lainnya',
      category:
          json['category'] is String ? json['category'] as String : 'Catatan',
      content: json['content'] is String ? json['content'] as String : '',
      createdAt: parsedDate ?? DateTime.now(),
      imagePath: json['imagePath'] is String ? json['imagePath'] as String : null,
    );
  }
}
