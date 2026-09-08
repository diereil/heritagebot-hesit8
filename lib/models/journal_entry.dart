class JournalEntry {
  final String id;
  final String userId;
  final String placeId;
  final String placeName;
  final String letter;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final String createdAt;
  final int createdAtMillis;

  const JournalEntry({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.placeName,
    required this.letter,
    required this.imagePaths,
    required this.videoPaths,
    required this.createdAt,
    required this.createdAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'placeId': placeId,
      'placeName': placeName,
      'letter': letter,
      'imagePaths': imagePaths,
      'videoPaths': videoPaths,
      'createdAt': createdAt,
      'createdAtMillis': createdAtMillis,
    };
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['createdAt'];
    final millisRaw = map['createdAtMillis'];

    int parsedMillis;

    if (millisRaw is int) {
      parsedMillis = millisRaw;
    } else if (millisRaw is num) {
      parsedMillis = millisRaw.toInt();
    } else {
      parsedMillis =
          DateTime.tryParse(
            createdAtRaw?.toString() ?? '',
          )?.millisecondsSinceEpoch ??
          0;
    }

    return JournalEntry(
      id: map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      placeId: map['placeId']?.toString() ?? '',
      placeName: map['placeName']?.toString() ?? '',
      letter: map['letter']?.toString() ?? '',
      imagePaths: _safeStringList(map['imagePaths']),
      videoPaths: _safeStringList(map['videoPaths']),
      createdAt: createdAtRaw?.toString() ?? '',
      createdAtMillis: parsedMillis,
    );
  }

  static List<String> _safeStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }

    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }

    return [];
  }
}
