import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../services/excel_import_queue_service.dart';
import '../services/excel_bulk_management_service.dart';
import '../services/receipt_settlement_service.dart';
import '../services/settlement_snapshot_service.dart';
import '../services/supabase_service.dart';

class ExcelUploadScreen extends StatefulWidget {
  const ExcelUploadScreen({super.key});

  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  final _queue = ExcelImportQueueService.instance;
  List<ExcelBulkBatch> _batches = const [];
  String? _route;
  int? _year;
  String? _voyage;
  bool _loadingBatches = true;
  bool _recalculating = false;
  String _recalculateMessage = '';

  String _message =
      '파일명에서 운송 경로·년도·항차를 먼저 확인해 즉시 접수합니다. '
      '접수 후에는 이 화면에서 나가 다른 업무를 해도 앱이 켜져 있는 동안 순차 처리됩니다.';

  @override
  void initState() {
    super.initState();
    _queue.addListener(_refresh);
    _loadBatches();
  }

  @override
  void dispose() {
    _queue.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<String> get _routes => _batches
      .map((e) => e.route)
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<int> get _years {
    final values = _batches
        .where((e) => _route == null || e.route == _route)
        .map((e) => e.year)
        .where((e) => e > 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  List<String> get _voyages {
    final values = _batches
        .where((e) =>
            (_route == null || e.route == _route) &&
            (_year == null || e.year == _year))
        .map((e) => e.voyage)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await ExcelBulkManagementService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _loadingBatches = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingBatches = false;
        _recalculateMessage = '현재 데이터 목록 조회 실패: $error';
      });
    }
  }

  Future<void> _recalculateSelected() async {
    if (_route == null || _year == null || _voyage == null || _recalculating) {
      return;
    }
    setState(() {
      _recalculating = true;
      _recalculateMessage = '현재 DB 기준으로 재연산 및 Update 중...';
    });

    try {
      await SupabaseService.client.rpc(
        'admin_finalize_excel_batch_rules',
        params: {
          'p_route': _route,
          'p_year': _year,
          'p_voyage': _voyage,
          'p_resequence': true,
        },
      );

      final rows = await ExcelBulkManagementService.instance.listRows(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
      );
      final settlement =
          await ReceiptSettlementService.instance.calculate(rows);
      final routeKey = RouteCatalog.keyFor(_route!);
      await SettlementSnapshotService.instance.save(
        routeKey: routeKey,
        routeLabel: _route!,
        year: _year!,
        voyage: _voyage!,
        settlement: settlement,
      );

      if (!mounted) return;
      setState(() {
        _recalculateMessage =
            '${_route!} · ${_year!}년 · ${_voyage!}항차 재연산 및 Update 완료';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _recalculateMessage = '재연산 및 Update 실패: $error');
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  Future<void> _pick() async {
    try {
      final accepted = await _queue.pickAndEnqueueOne();
      if (!mounted) return;
      setState(() {
        _message = accepted
            ? '파일 접수 완료. 바로 다른 화면으로 이동하거나, 아래 버튼을 다시 눌러 다음 파일도 계속 추가할 수 있습니다.'
            : '파일을 선택하지 않았거나 기본 파일명 검사를 통과하지 못했습니다.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '파일 접수 실패: $error');
    }
  }

  Color _statusColor(ExcelImportJobStatus status) {
    switch (status) {
      case ExcelImportJobStatus.completed:
        return Colors.green;
      case ExcelImportJobStatus.warning:
        return Colors.orange;
      case ExcelImportJobStatus.failed:
        return Colors.redAccent;
      case ExcelImportJobStatus.processing:
        return AppColors.primary;
      case ExcelImportJobStatus.queued:
        return Colors.blueGrey;
    }
  }

  String _statusText(ExcelImportJobStatus status) {
    switch (status) {
      case ExcelImportJobStatus.completed:
        return '완료';
      case ExcelImportJobStatus.warning:
        return '완료 · 확인 필요';
      case ExcelImportJobStatus.failed:
        return '실패';
      case ExcelImportJobStatus.processing:
        return '작업 중';
      case ExcelImportJobStatus.queued:
        return '대기';
    }
  }

  Widget _jobCard(ExcelImportJob job) {
    final color = _statusColor(job.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  job.status == ExcelImportJobStatus.processing
                      ? '% 진행중'
                      : _statusText(job.status),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${job.routeLabel} · '
              '${job.year == 0 ? '-' : '${job.year}년'} · '
              '${job.voyage == '-' ? '-' : '${job.voyage}항차'}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.progress,
              minHeight: 8,
            ),
            const SizedBox(height: 7),
            Text(
              job.message,
              style: TextStyle(
                fontSize: 12,
                color: job.status == ExcelImportJobStatus.failed
                    ? Colors.redAccent
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('화물 데이타 엑셀 업로드 및 Update'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '관리자·직원·협력/파트너사 전용',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '기초 접수 검사: XLSX 파일명 · 운송 경로 · 년도 · 항차\n'
                '예: KR_LA_SEA_2026_V08_SHIPMENTS.xlsx\n\n'
                '접수 후 Excel 분석, 중복 정리, 화물 DB 반영은 순차 처리됩니다.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.add_to_queue),
                label: const Text('Excel 파일 추가 / 업로드 접수'),
              ),
              const SizedBox(height: 10),
              Text(
                _message,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              const Divider(height: 34),
              const Text(
                '현재 데이터 재연산 및 Update',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                '직접 데이터 수정 또는 고객/배송/할인 규칙 변경 후 반영이 의심될 때 '
                '선택 항차의 영수번호·구획·자동 특이사항·할인/정산을 다시 계산합니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingBatches)
                const LinearProgressIndicator()
              else ...[
                DropdownButtonFormField<String>(
                  value: _route,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로',
                    border: OutlineInputBorder(),
                  ),
                  items: _routes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: _recalculating
                      ? null
                      : (value) {
                          setState(() {
                            _route = value;
                            _year = null;
                            _voyage = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _year,
                  decoration: const InputDecoration(
                    labelText: '년도',
                    border: OutlineInputBorder(),
                  ),
                  items: _years
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text('$e년')))
                      .toList(),
                  onChanged: _route == null || _recalculating
                      ? null
                      : (value) {
                          setState(() {
                            _year = value;
                            _voyage = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _voyage,
                  decoration: const InputDecoration(
                    labelText: '항차',
                    border: OutlineInputBorder(),
                  ),
                  items: _voyages
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text('${e}항차'),
                          ))
                      .toList(),
                  onChanged: _year == null || _recalculating
                      ? null
                      : (value) => setState(() => _voyage = value),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _route == null ||
                          _year == null ||
                          _voyage == null ||
                          _recalculating
                      ? null
                      : _recalculateSelected,
                  icon: _recalculating
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('재연산 및 Update'),
                ),
              ],
              if (_recalculateMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _recalculateMessage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (_queue.jobs.isNotEmpty) ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '업로드 / 처리 작업 현황',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (!_queue.isProcessing && _queue.pendingCount == 0)
                      TextButton(
                        onPressed: _queue.clearFinished,
                        child: const Text('완료 목록 지우기'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._queue.jobs.map(_jobCard),
              ],
            ],
          ),
        ),
      );
}

