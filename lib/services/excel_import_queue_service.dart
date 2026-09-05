import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import 'excel_file_metadata.dart';
import 'excel_import_service.dart';
import 'global_notice_service.dart';

enum ExcelImportJobStatus {
  queued,
  processing,
  completed,
  warning,
  failed,
}

class ExcelImportJob {
  ExcelImportJob({
    required this.id,
    required this.fileName,
    required this.bytes,
    required this.routeLabel,
    required this.year,
    required this.voyage,
  });

  final String id;
  final String fileName;
  final Uint8List bytes;
  final String routeLabel;
  final int year;
  final String voyage;

  ExcelImportJobStatus status = ExcelImportJobStatus.queued;
  double progress = 0.08;
  String message = '접수 완료 · 처리 대기';
}

class ExcelImportQueueService extends ChangeNotifier {
  ExcelImportQueueService._();
  static final ExcelImportQueueService instance = ExcelImportQueueService._();

  final List<ExcelImportJob> _jobs = <ExcelImportJob>[];
  bool _draining = false;

  List<ExcelImportJob> get jobs => List.unmodifiable(_jobs);
  bool get isProcessing => _draining;
  int get pendingCount => _jobs.where((job) =>
      job.status == ExcelImportJobStatus.queued ||
      job.status == ExcelImportJobStatus.processing).length;

  Future<bool> pickAndEnqueueOne() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ExcelFileMetadataParser.supportedExtensions,
    );
    if (picked == null) return false;

    final meta = ExcelFileMetadataParser.tryParse(picked.name);
    if (meta == null) {
      _jobs.insert(
        0,
        ExcelImportJob(
          id: '${DateTime.now().microsecondsSinceEpoch}-${picked.name}',
          fileName: picked.name,
          bytes: Uint8List(0),
          routeLabel: '-',
          year: 0,
          voyage: '-',
        )
          ..status = ExcelImportJobStatus.failed
          ..progress = 1
          ..message =
              '파일명 확인 필요 · 경로(LKS/KR_LA_SEA), 연도(2026), '
              '항차(V08/08항차)가 들어가야 합니다. 설명 문구는 자유롭게 추가할 수 있습니다.',
      );
      notifyListeners();
      return false;
    }

    final bytes = await picked.readAsBytes();
    final job = ExcelImportJob(
      id: '${DateTime.now().microsecondsSinceEpoch}-${picked.name}',
      fileName: picked.name,
      bytes: bytes,
      routeLabel: meta.routeLabel,
      year: meta.year,
      voyage: meta.voyage,
    );
    _jobs.insert(0, job);
    notifyListeners();

    if (!_draining) unawaited(_drain());
    return true;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    notifyListeners();

    try {
      while (true) {
        ExcelImportJob? next;
        for (final job in _jobs.reversed) {
          if (job.status == ExcelImportJobStatus.queued) {
            next = job;
            break;
          }
        }
        if (next == null) break;

        next.status = ExcelImportJobStatus.processing;
        next.progress = 0.12;
        next.message = '12% · Excel 구조 확인 중';
        notifyListeners();

        try {
          final result = await ExcelImportService.instance.importBytes(
            next.bytes,
            fileName: next.fileName,
            onProgress: (progress, message) {
              next!.progress = progress;
              next.message = '${(progress * 100).round()}% · $message';
              notifyListeners();
            },
          );
          next.progress = 1;
          next.status = result.customerRulesWaitingForPhone > 0
              ? ExcelImportJobStatus.warning
              : ExcelImportJobStatus.completed;
          next.message =
              '작업 완료 · 화물 ${result.inserted}건 · 비화물 ${result.skipped}건'
              '${result.customerRulesWaitingForPhone > 0 ? ' · 할인 전화번호 대기 ${result.customerRulesWaitingForPhone}건' : ''}';
          GlobalNoticeService.instance.show(
            '업로드 완료 · ${next.routeLabel} · ${next.year}년 · ${next.voyage}항차'
            '${next.status == ExcelImportJobStatus.warning ? ' · 확인 필요' : ''}',
          );
        } catch (error) {
          next.progress = 1;
          next.status = ExcelImportJobStatus.failed;
          next.message = '처리 실패: $error';
          GlobalNoticeService.instance.show(
            '업로드 실패 · ${next.routeLabel} · ${next.year}년 · ${next.voyage}항차', error: true);
        }

        notifyListeners();
      }
    } finally {
      _draining = false;
      notifyListeners();
    }
  }

  void clearFinished() {
    _jobs.removeWhere((job) =>
        job.status == ExcelImportJobStatus.completed ||
        job.status == ExcelImportJobStatus.warning ||
        job.status == ExcelImportJobStatus.failed);
    notifyListeners();
  }

}
