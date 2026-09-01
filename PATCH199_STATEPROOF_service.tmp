import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/route_catalog.dart';
import 'excel_bulk_management_service.dart';
import 'global_notice_service.dart';
import 'receipt_settlement_service.dart';
import 'settlement_snapshot_service.dart';
import 'supabase_service.dart';

class RecalculationJobService extends ChangeNotifier {
  RecalculationJobService._();

  static final RecalculationJobService instance = RecalculationJobService._();

  bool _running = false;
  String _message = '';
  String _step = '';
  Object? _lastError;
  StackTrace? _lastStackTrace;
  Future<void>? _activeJob;

  bool get running => _running;
  String get message => _message;
  String get step => _step;
  Object? get lastError => _lastError;
  StackTrace? get lastStackTrace => _lastStackTrace;

  Future<bool> start({
    required String route,
    required int year,
    required String voyage,
  }) async {
    if (_running) {
      _message = '이미 재연산이 진행 중입니다.';
      notifyListeners();
      return false;
    }

    _running = true;
    _lastError = null;
    _lastStackTrace = null;
    _step = '시작';
    _message = '$route · ${year}년 · ${voyage}항차 재연산 시작';
    notifyListeners();

    // Keep a strong reference to the entire job for the lifetime of the app process.
    // Route navigation/dispose cannot cancel this Future.
    _activeJob = _run(route: route, year: year, voyage: voyage);
    unawaited(_activeJob);
    return true;
  }

  Future<void> _run({
    required String route,
    required int year,
    required String voyage,
  }) async {
    try {
      await _stage(
        'XX 영수번호 정리',
        () => SupabaseService.client.rpc(
          'admin_prepare_resolved_unknown_receipts',
          params: {
            'p_route': route,
            'p_year': year,
            'p_voyage': voyage,
          },
        ),
      );

      await _stage(
        '영수번호·Zone·규칙 재계산',
        () => SupabaseService.client.rpc(
          'admin_finalize_excel_batch_rules',
          params: {
            'p_route': route,
            'p_year': year,
            'p_voyage': voyage,
            'p_resequence': true,
          },
        ),
      );

      await _stage(
        'Remark 중복 정리',
        () => SupabaseService.client.rpc(
          'admin_cleanup_batch_remarks',
          params: {
            'p_route': route,
            'p_year': year,
            'p_voyage': voyage,
          },
        ),
      );

      _setStage('화물 데이터 다시 읽기');
      final rows = await ExcelBulkManagementService.instance.listRows(
        route: route,
        year: year,
        voyage: voyage,
      );

      _setStage('할인·정산 재계산');
      final settlement = await ReceiptSettlementService.instance.calculate(rows);

      _setStage('정산 Snapshot 저장');
      await SettlementSnapshotService.instance.save(
        routeKey: RouteCatalog.keyFor(route),
        routeLabel: route,
        year: year,
        voyage: voyage,
        settlement: settlement,
      );

      _step = '완료';
      _message = '$route · ${year}년 · ${voyage}항차 재연산 및 Update 완료';
      debugPrint('[RECALC] COMPLETE: $_message');
      _safeNotice(_message);
    } catch (error, stackTrace) {
      _lastError = error;
      _lastStackTrace = stackTrace;
      _message = '재연산 실패 ($_step): $error';
      debugPrint('[RECALC] ERROR at $_step: $error');
      debugPrintStack(stackTrace: stackTrace);
      _safeNotice(_message, error: true);
    } finally {
      _running = false;
      _activeJob = null;
      notifyListeners();
    }
  }

  Future<void> _stage(
    String name,
    Future<dynamic> Function() action,
  ) async {
    _setStage(name);

    // One retry for transient transport/connection failures.
    try {
      await action();
    } catch (firstError) {
      debugPrint('[RECALC] retry $name after: $firstError');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await action();
    }
  }

  void _setStage(String value) {
    _step = value;
    _message = '재연산 중 · $value';
    debugPrint('[RECALC] $_message');
    notifyListeners();
  }

  void _safeNotice(String text, {bool error = false}) {
    try {
      GlobalNoticeService.instance.show(text, error: error);
    } catch (noticeError, noticeStack) {
      // A route transition must never turn a completed recalculation into a failure.
      debugPrint('[RECALC] notice skipped: $noticeError');
      debugPrintStack(stackTrace: noticeStack);
    }
  }
}
