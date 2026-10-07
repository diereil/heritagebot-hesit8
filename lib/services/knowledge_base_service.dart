import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/community_submission.dart';
import '../models/heritage_place.dart';
import '../models/historical_content.dart';
import 'gemini_embedding_service.dart';

class KnowledgeBaseStatus {
  final int total;
  final int approved;
  final int vectorReady;
  final int missingVector;
  final int communitySources;

  const KnowledgeBaseStatus({
    required this.total,
    required this.approved,
    required this.vectorReady,
    required this.missingVector,
    required this.communitySources,
  });
}

class RagRetrievalResult {
  final List<HistoricalContent> documents;
  final String context;
  final String retrievalMode;

  const RagRetrievalResult({
    required this.documents,
    required this.context,
    required this.retrievalMode,
  });

  List<String> get documentIds => documents.map((item) => item.id).toList();

  List<String> get sourceTitles => documents
      .map((item) => item.sourceTitle.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

class KnowledgeBaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GeminiEmbeddingService _embeddingService;

  KnowledgeBaseService({required String geminiApiKey})
    : _embeddingService = GeminiEmbeddingService(apiKey: geminiApiKey);

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('historical_contents');

  Future<List<HistoricalContent>> getAllContent() async {
    final snapshot = await _collection.get();

    final items = snapshot.docs
        .map((doc) => HistoricalContent.fromMap(doc.data(), documentId: doc.id))
        .toList();

    items.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    return items;
  }

  KnowledgeBaseStatus statusFrom(List<HistoricalContent> items) {
    return KnowledgeBaseStatus(
      total: items.length,
      approved: items.where((item) => item.isApproved).length,
      vectorReady: items.where((item) => item.hasEmbedding).length,
      missingVector: items.where((item) => !item.hasEmbedding).length,
      communitySources: items
          .where((item) => item.sourceType == 'community')
          .length,
    );
  }

  Future<HistoricalContent> addContent({
    required String siteId,
    required String siteName,
    required String title,
    required String content,
    required String sourceTitle,
    required String sourceUrl,
    required String category,
    required String languageCode,
    required bool isApproved,
    String sourceType = 'curated',
    String sourceRefId = '',
  }) async {
    _validate(title: title, content: content, sourceTitle: sourceTitle);

    final reference = _collection.doc();
    final now = DateTime.now().millisecondsSinceEpoch;

    final embedding = await _embeddingService.embedDocument(
      _embeddingInput(
        siteName: siteName,
        title: title,
        content: content,
        sourceTitle: sourceTitle,
      ),
    );

    final item = HistoricalContent(
      id: reference.id,
      siteId: siteId,
      siteName: siteName.trim(),
      title: title.trim(),
      content: content.trim(),
      sourceTitle: sourceTitle.trim(),
      sourceUrl: sourceUrl.trim(),
      category: category.trim().isEmpty ? 'historical_record' : category.trim(),
      languageCode: languageCode.trim().isEmpty ? 'en' : languageCode.trim(),
      sourceType: sourceType,
      sourceRefId: sourceRefId,
      isApproved: isApproved,
      embedding: embedding,
      embeddingModel: GeminiEmbeddingService.modelName,
      createdAtMillis: now,
      updatedAtMillis: now,
    );

    await reference.set(item.toMap());
    return item;
  }

  Future<void> updateContent(HistoricalContent item) async {
    _validate(
      title: item.title,
      content: item.content,
      sourceTitle: item.sourceTitle,
    );

    final embedding = await _embeddingService.embedDocument(
      _embeddingInput(
        siteName: item.siteName,
        title: item.title,
        content: item.content,
        sourceTitle: item.sourceTitle,
      ),
    );

    await _collection.doc(item.id).update({
      ...item.toMap(),
      'embedding': embedding,
      'embeddingModel': GeminiEmbeddingService.modelName,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteContent(String id) async {
    await _collection.doc(id).delete();
  }

  Future<int> initializeSiteFacts(List<HeritagePlace> sites) async {
    var created = 0;

    for (final site in sites) {
      final id = 'site_${site.id}';
      final existing = await _collection.doc(id).get();

      if (existing.exists) {
        continue;
      }

      final embedding = await _embeddingService.embedDocument(
        _embeddingInput(
          siteName: site.name,
          title: '${site.name} historical background',
          content: site.historicalFacts,
          sourceTitle: 'HeritageBot curated site record',
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      await _collection.doc(id).set({
        'siteId': site.id,
        'siteName': site.name,
        'title': '${site.name} historical background',
        'content': site.historicalFacts,
        'sourceTitle': 'HeritageBot curated site record',
        'sourceUrl': '',
        'category': 'historical_background',
        'languageCode': 'en',
        'sourceType': 'curated',
        'sourceRefId': site.id,
        'isApproved': true,
        'embedding': embedding,
        'embeddingModel': GeminiEmbeddingService.modelName,
        'createdAtMillis': now,
        'updatedAtMillis': now,
      });

      created++;
    }

    return created;
  }

  Future<int> syncApprovedCommunityStories(
    List<CommunitySubmission> submissions,
  ) async {
    var synced = 0;

    for (final submission in submissions) {
      if (submission.status != CommunitySubmissionStatus.approved) {
        continue;
      }

      final id = 'community_${submission.id}';

      final embedding = await _embeddingService.embedDocument(
        _embeddingInput(
          siteName: submission.heritagePlaceName,
          title: submission.title,
          content: submission.story,
          sourceTitle:
              'Approved community story by ${submission.contributorName}',
        ),
      );

      final existing = await _collection.doc(id).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      final createdAt = existing.data()?['createdAtMillis'] as num?;

      await _collection.doc(id).set({
        'siteId': submission.heritagePlaceId,
        'siteName': submission.heritagePlaceName,
        'title': submission.title,
        'content': submission.story,
        'sourceTitle':
            'Approved community story by ${submission.contributorName}',
        'sourceUrl': '',
        'category': 'community_story',
        'languageCode': 'en',
        'sourceType': 'community',
        'sourceRefId': submission.id,
        'isApproved': true,
        'embedding': embedding,
        'embeddingModel': GeminiEmbeddingService.modelName,
        'createdAtMillis': createdAt?.toInt() ?? now,
        'updatedAtMillis': now,
      });

      synced++;
    }

    return synced;
  }

  Future<int> rebuildAllEmbeddings() async {
    final items = await getAllContent();
    var rebuilt = 0;

    for (final item in items) {
      final embedding = await _embeddingService.embedDocument(
        _embeddingInput(
          siteName: item.siteName,
          title: item.title,
          content: item.content,
          sourceTitle: item.sourceTitle,
        ),
      );

      await _collection.doc(item.id).update({
        'embedding': embedding,
        'embeddingModel': GeminiEmbeddingService.modelName,
        'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      });

      rebuilt++;
    }

    return rebuilt;
  }

  Future<RagRetrievalResult> retrieveForSite({
    required HeritagePlace place,
    required String query,
    int limit = 4,
  }) async {
    try {
      final snapshot = await _collection
          .where('siteId', isEqualTo: place.id)
          .get();

      final candidates = snapshot.docs
          .map(
            (doc) => HistoricalContent.fromMap(doc.data(), documentId: doc.id),
          )
          .where((item) => item.isApproved && item.hasEmbedding)
          .toList();

      if (candidates.isEmpty) {
        return _fallback(place);
      }

      final queryEmbedding = await _embeddingService.embedQuery(query);

      final scored =
          candidates
              .map(
                (item) => (
                  item: item,
                  score: _cosineSimilarity(queryEmbedding, item.embedding),
                ),
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));

      final selected = scored
          .take(math.max(1, math.min(limit, scored.length)))
          .map((entry) => entry.item)
          .toList();

      final context = selected
          .map((item) {
            final source = item.sourceTitle.trim().isEmpty
                ? 'Verified HeritageBot source'
                : item.sourceTitle.trim();

            return '''
SOURCE: $source
TITLE: ${item.title}
CONTENT: ${item.content}
''';
          })
          .join('\n');

      return RagRetrievalResult(
        documents: selected,
        context: context,
        retrievalMode: 'vector_rag',
      );
    } catch (_) {
      return _fallback(place);
    }
  }

  RagRetrievalResult _fallback(HeritagePlace place) {
    return RagRetrievalResult(
      documents: const [],
      context:
          '''
SOURCE: HeritageBot site record
TITLE: ${place.name}
CONTENT: ${place.historicalFacts}
''',
      retrievalMode: 'site_facts_fallback',
    );
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    final length = math.min(a.length, b.length);

    if (length == 0) {
      return -1;
    }

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) {
      return -1;
    }

    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  String _embeddingInput({
    required String siteName,
    required String title,
    required String content,
    required String sourceTitle,
  }) {
    return '''
Heritage Site: $siteName
Title: $title
Source: $sourceTitle
Historical Content:
$content
''';
  }

  void _validate({
    required String title,
    required String content,
    required String sourceTitle,
  }) {
    if (title.trim().length < 3) {
      throw ArgumentError('Historical data title is required.');
    }

    if (content.trim().length < 30) {
      throw ArgumentError(
        'Historical content must contain at least 30 characters.',
      );
    }

    if (sourceTitle.trim().length < 3) {
      throw ArgumentError(
        'Please identify the source of this historical content.',
      );
    }
  }
}
