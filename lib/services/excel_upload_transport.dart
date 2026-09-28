import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

bool isRetryableExcelUpload(Object error) {
  if (error is TimeoutException) return true;
  if (error is StorageException) {
    final status = int.tryParse('${error.statusCode}');
    if (status != null) return status == 408 || status == 429 || status >= 500;
  }
  return RegExp(r'Failed to fetch|NetworkError|network request failed|SocketException|ClientException.*(connection|socket|network)|connection reset|connection closed|timed out', caseSensitive: false).hasMatch('$error');
}

Future<T> retryExcelSourceUpload<T>(Future<T> Function() upload, {
  Future<void> Function(Duration)? wait,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await upload().timeout(const Duration(seconds: 90));
    } catch (error) {
      if (!isRetryableExcelUpload(error)) rethrow;
      if (attempt == 3) {
        throw StateError('원본 파일 전송을 완료하지 못했습니다. 인터넷 연결을 확인한 후 다시 업로드해 주세요.');
      }
      await (wait ?? (duration) => Future<void>.delayed(duration))(Duration(seconds: attempt));
    }
  }
}

String excelSourceObjectPath(String routeKey, int year, String voyage, String fileName) {
  final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final random = Random.secure();
  final uploadId = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '$routeKey/$year/V$voyage/${uploadId}_$safeName';
}
