class HistoricalContent {
  final String id;
  final String siteId;
  final String siteName;
  final String title;
  final String content;
  final String sourceTitle;
  final String sourceUrl;
  final String category;
  final String languageCode;
  final String sourceType;
  final String sourceRefId;
  final bool isApproved;
  final List<double> embedding;
  final String embeddingModel;
  final int createdAtMillis;
  final int updatedAtMillis;

  const HistoricalContent({
    required this.id,
    required this.siteId,
    required this.siteName,
    required this.title,
    required this.content,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.category,
    required this.languageCode,
    required this.sourceType,
    required this.sourceRefId,
    required this.isApproved,
    required this.embedding,
    required this.embeddingModel,
    required this.createdAtMillis,
    required this.updatedAtMillis,
  });

  bool get hasEmbedding => embedding.isNotEmpty;

  HistoricalContent copyWith({
    String? id,
    String? siteId,
    String? siteName,
    String? title,
    String? content,
    String? sourceTitle,
    String? sourceUrl,
    String? category,
    String? languageCode,
    String? sourceType,
    String? sourceRefId,
    bool? isApproved,
    List<double>? embedding,
    String? embeddingModel,
    int? createdAtMillis,
    int? updatedAtMillis,
  }) {
    return HistoricalContent(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      siteName: siteName ?? this.siteName,
      title: title ?? this.title,
      content: content ?? this.content,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      category: category ?? this.category,
      languageCode: languageCode ?? this.languageCode,
      sourceType: sourceType ?? this.sourceType,
      sourceRefId: sourceRefId ?? this.sourceRefId,
      isApproved: isApproved ?? this.isApproved,
      embedding: embedding ?? List<double>.of(this.embedding),
      embeddingModel: embeddingModel ?? this.embeddingModel,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'siteName': siteName,
      'title': title,
      'content': content,
      'sourceTitle': sourceTitle,
      'sourceUrl': sourceUrl,
      'category': category,
      'languageCode': languageCode,
      'sourceType': sourceType,
      'sourceRefId': sourceRefId,
      'isApproved': isApproved,
      'embedding': embedding,
      'embeddingModel': embeddingModel,
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory HistoricalContent.fromMap(
    Map<String, dynamic> map, {
    required String documentId,
  }) {
    final rawEmbedding = map['embedding'];

    return HistoricalContent(
      id: documentId,
      siteId: map['siteId']?.toString() ?? '',
      siteName: map['siteName']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      sourceTitle: map['sourceTitle']?.toString() ?? '',
      sourceUrl: map['sourceUrl']?.toString() ?? '',
      category: map['category']?.toString() ?? 'historical_record',
      languageCode: map['languageCode']?.toString() ?? 'en',
      sourceType: map['sourceType']?.toString() ?? 'curated',
      sourceRefId: map['sourceRefId']?.toString() ?? '',
      isApproved: map['isApproved'] == true,
      embedding: rawEmbedding is List
          ? rawEmbedding
                .whereType<num>()
                .map((value) => value.toDouble())
                .toList()
          : const [],
      embeddingModel: map['embeddingModel']?.toString() ?? '',
      createdAtMillis: (map['createdAtMillis'] as num?)?.toInt() ?? 0,
      updatedAtMillis: (map['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }
}
