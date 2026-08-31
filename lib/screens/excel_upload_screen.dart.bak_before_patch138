import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../services/excel_import_queue_service.dart';

class ExcelUploadScreen extends StatefulWidget {
  const ExcelUploadScreen({super.key});

  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  final _queue = ExcelImportQueueService.instance;
  String _message =
      '파일명에서 운송 경로·년도·항차를 먼저 확인해 즉시 접수합니다. '
      '접수 후에는 이 화면에서 나가 다른 업무를 해도 앱이 켜져 있는 동안 순차 처리됩니다.';

  @override
  void initState() {
    super.initState();
    _queue.addListener(_refresh);
  }

  @override
  void dispose() {
    _queue.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    final working = job.status == ExcelImportJobStatus.processing;

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
                  _statusText(job.status),
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
              value: working ? null : job.progress,
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
          title: const Text('화물 데이타 엑셀 업로드'),
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
