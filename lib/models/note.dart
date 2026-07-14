class Note {
  final String url;
  final String editCode;
  final String title;
  final DateTime updatedAt;
  final bool isSynced;
  final int colorValue;
  final String metadata;

  Note({
    required this.url,
    required this.editCode,
    required this.title,
    required this.updatedAt,
    required this.isSynced,
    required this.colorValue,
    required this.metadata,
  });

  Note copyWith({
    String? url,
    String? editCode,
    String? title,
    DateTime? updatedAt,
    bool? isSynced,
    int? colorValue,
    String? metadata,
  }) {
    return Note(
      url: url ?? this.url,
      editCode: editCode ?? this.editCode,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      colorValue: colorValue ?? this.colorValue,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'edit_code': editCode,
      'title': title,
      'updated_at': updatedAt.toIso8601String(),
      'is_synced': isSynced,
      'color_value': colorValue,
      'metadata': metadata,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      url: json['url'] as String,
      editCode: json['edit_code'] as String,
      title: json['title'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isSynced: json['is_synced'] as bool,
      colorValue: json['color_value'] as int,
      metadata: (json['metadata'] as String?) ?? '',
    );
  }
}
