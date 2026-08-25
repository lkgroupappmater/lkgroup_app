// lib/services/quote_service.dart

class QuoteService {
  QuoteService._();
  static final QuoteService instance = QuoteService._();

  final List<Map<String, dynamic>> _quotes = [];

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// 새 견적을 생성하고 저장한 뒤 반환합니다.
  Map<String, dynamic> create(Map<String, dynamic> data) {
    final quote = <String, dynamic>{
      'id': _generateId(),
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      ...data,
    };
    _quotes.add(quote);
    return quote;
  }

  /// [create]의 별칭 — 기존 코드 호환용.
  Map<String, dynamic> submit(Map<String, dynamic> data) => create(data);

  /// 저장된 모든 견적을 반환합니다.
  List<Map<String, dynamic>> getAll() => List.unmodifiable(_quotes);

  /// ID로 견적을 조회합니다.
  Map<String, dynamic>? findById(String id) {
    try {
      return _quotes.firstWhere((q) => q['id'] == id);
    } catch (_) {
      return null;
    }
  }

  /// ID로 견적을 삭제합니다.
  bool delete(String id) {
    final before = _quotes.length;
    _quotes.removeWhere((q) => q['id'] == id);
    return _quotes.length < before;
  }
}
