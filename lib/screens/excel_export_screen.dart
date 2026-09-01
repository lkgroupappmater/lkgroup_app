import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../services/excel_bulk_management_service.dart';
import '../services/excel_export_service.dart';
import '../services/excel_import_queue_service.dart';
import '../services/receipt_settlement_service.dart';
import '../services/settlement_snapshot_service.dart';
import '../services/supabase_service.dart';

class ExcelExportScreen extends StatefulWidget {
  const ExcelExportScreen({super.key});

  @override
  State<ExcelExportScreen> createState() => _ExcelExportScreenState();
}

class _ExcelExportScreenState extends State<ExcelExportScreen> {
  final _queue = ExcelImportQueueService.instance;

  bool _loading = true;
  bool _exporting = false;
  bool _recalculating = false;
  double _recalcProgress = 0;
  String _recalcText = '';
  String _message = '';

  List<ExcelExportBatch> _batches = const [];
  String? _route;
  int? _year;
  String? _voyage;

  List<String> get _routes =>
      _batches.map((e) => e.routeLabel).toSet().toList()..sort();

  List<int> get _years {
    final values = _batches
        .where((e) => e.routeLabel == _route)
        .map((e) => e.year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  List<String> get _voyages {
    final values = _batches
        .where((e) => e.routeLabel == _route && e.year == _year)
        .map((e) => e.voyage)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return values;
  }

  ExcelExportBatch? get _selected {
    if (_route == null || _year == null || _voyage == null) return null;
    for (final b in _batches) {
      if (b.routeLabel == _route &&
          b.year == _year &&
          b.voyage == _voyage) {
        return b;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _queue.addListener(_queueRefresh);
    _load();
  }

  @override
  void dispose() {
    _queue.removeListener(_queueRefresh);
    super.dispose();
  }

  void _queueRefresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final batches = await ExcelExportService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _route = null;
        _year = null;
        _voyage = null;
        _message = batches.isEmpty
            ? '실제 화물 데이터가 등록된 운송 경로/년도/항차가 없습니다.'
            : '업로드는 위 버튼에서 바로 실행하고, 재연산/다운로드만 아래 항차 선택값을 사용합니다.';
      });
    } catch (e) {
      if (mounted) setState(() => _message = '목록 불러오기 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    try {
      final accepted = await _queue.pickAndEnqueueOne();
      if (!mounted) return;
      setState(() {
        _message = accepted
            ? '업로드 접수 완료. 아래 업로드 진행 현황을 확인하세요.'
            : '파일 선택 취소 또는 파일명 확인 필요.';
      });
    } catch (e) {
      if (mounted) setState(() => _message = '업로드 접수 실패: $e');
    }
  }

  Future<void> _recalculate() async {
    final selected = _selected;
    if (selected == null || _recalculating) return;

    setState(() {
      _recalculating = true;
      _recalcProgress = 0.10;
      _recalcText = '10% · 선택 항차 확인';
      _message = '';
    });

    try {
      setState(() {
        _recalcProgress = 0.20;
        _recalcText = '20% · 영수번호 / Zone / 고객 규칙 재연산';
      });

      await SupabaseService.client.rpc(
        'admin_finalize_excel_batch_rules_fast',
        params: {
          'p_route': selected.routeLabel,
          'p_year': selected.year,
          'p_voyage': selected.voyage,
          'p_resequence': true,
        },
      );

      if (!mounted) return;
      setState(() {
        _recalcProgress = 0.72;
        _recalcText = '72% · 최신 화물 데이터 다시 읽는 중';
      });

      final rows = await ExcelBulkManagementService.instance.listRows(
        route: selected.routeLabel,
        year: selected.year,
        voyage: selected.voyage,
      );

      if (!mounted) return;
      setState(() {
        _recalcProgress = 0.84;
        _recalcText = '84% · 할인 / 운임 재계산';
      });

      final settlement =
          await ReceiptSettlementService.instance.calculate(rows);

      if (!mounted) return;
      setState(() {
        _recalcProgress = 0.94;
        _recalcText = '94% · 정산 snapshot 갱신';
      });

      await SettlementSnapshotService.instance.save(
        routeKey: RouteCatalog.keyFor(selected.routeLabel),
        routeLabel: selected.routeLabel,
        year: selected.year,
        voyage: selected.voyage,
        settlement: settlement,
      );

      if (!mounted) return;
      setState(() {
        _recalcProgress = 1;
        _recalcText = '100% · 완료';
        _message =
            '${selected.routeLabel} · ${selected.year}년 · ${selected.voyage}항차 재연산 및 Update 완료';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recalcProgress = 1;
        _recalcText = '실패';
        _message = '재연산 및 Update 실패: $e';
      });
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  Future<void> _export() async {
    final selected = _selected;
    if (selected == null || _exporting) return;
    setState(() {
      _exporting = true;
      _message = '원본 Excel 모양을 유지하면서 최신 자료를 반영 중입니다...';
    });
    try {
      final result = await ExcelExportService.instance.exportAndSave(selected);
      if (!mounted) return;
      setState(() {
        _message = result.saved
            ? '${result.message}\n파일: ${result.fileName}'
                '${result.savedLocation.isEmpty ? '' : '\n저장 위치: ${result.savedLocation}'}'
            : result.message;
      });
    } catch (e) {
      if (mounted) setState(() => _message = '다운로드 실패: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Color _jobColor(ExcelImportJobStatus status) {
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

  String _jobText(ExcelImportJobStatus status) {
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

  Widget _jobCard(ExcelImportJob job) => Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    _jobText(job.status),
                    style: TextStyle(
                      color: _jobColor(job.status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: job.progress),
              const SizedBox(height: 5),
              Text(
                job.message,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('화물 데이타 엑셀 다운로드'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        backgroundColor: AppColors.background,
        body: ListView(
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
            const SizedBox(height: 12),

            // 업로드는 항차 선택과 완전히 독립.
            FilledButton.icon(
              onPressed: _recalculating ? null : _upload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Excel 파일 업로드'),
            ),

            if (_queue.jobs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                '업로드 진행 현황',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              ..._queue.jobs.take(3).map(_jobCard),
            ],

            const Divider(height: 32),

            const Text(
              '재연산 / 다운로드 대상 선택',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              '아래 운송 경로·년도·항차는 재연산 또는 다운로드에만 사용됩니다.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_batches.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _route,
                isExpanded: true,
                decoration: _dec('운송 경로'),
                items: _routes
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: _exporting || _recalculating
                    ? null
                    : (v) => setState(() {
                          _route = v;
                          _year = null;
                          _voyage = null;
                        }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                key: ValueKey('year-$_route'),
                initialValue: _year,
                decoration: _dec('년도'),
                items: _years
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text('$v년'),
                        ))
                    .toList(),
                onChanged: _route == null || _exporting || _recalculating
                    ? null
                    : (v) => setState(() {
                          _year = v;
                          _voyage = null;
                        }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('voyage-$_route-$_year'),
                initialValue: _voyage,
                decoration: _dec('항차'),
                items: _voyages
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.endsWith('항차') ? v : '$v항차'),
                        ))
                    .toList(),
                onChanged: _year == null || _exporting || _recalculating
                    ? null
                    : (v) => setState(() => _voyage = v),
              ),
            ],

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _selected == null || _recalculating || _exporting
                  ? null
                  : _recalculate,
              icon: const Icon(Icons.sync),
              label: const Text('선택 항차 재연산 및 Update'),
            ),

            if (_recalculating || _recalcText.isNotEmpty) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _recalcProgress <= 0 ? null : _recalcProgress,
              ),
              const SizedBox(height: 5),
              Text(
                _recalcText,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: 10),

            FilledButton.icon(
              onPressed: _selected == null || _exporting || _recalculating
                  ? null
                  : _export,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                _exporting
                    ? 'Excel 생성 중...'
                    : 'Excel 다운로드 및 저장 위치 선택',
              ),
            ),

            const SizedBox(height: 18),
            Text(
              _message,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}
