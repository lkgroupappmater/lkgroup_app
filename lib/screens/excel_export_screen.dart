import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../services/excel_export_service.dart';

class ExcelExportScreen extends StatefulWidget {
  const ExcelExportScreen({super.key});

  @override
  State<ExcelExportScreen> createState() => _ExcelExportScreenState();
}

class _ExcelExportScreenState extends State<ExcelExportScreen> {
  bool _loading = true;
  bool _exporting = false;
  String _message = '';
  List<ExcelExportBatch> _batches = const [];
  ExcelExportBatch? _selected;

  @override
  void initState() {
    super.initState();
    _load();
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
        _selected = batches.isEmpty ? null : batches.first;
        _message = batches.isEmpty
            ? 'DB에 운송 경로/연도/항차가 지정된 화물 자료가 없습니다.'
            : 'DB의 운송 경로/연도/항차를 선택해 주세요. 항차별 변경 폼이 있으면 우선 적용하고, 없으면 기본 폼을 사용합니다.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '목록 불러오기 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      final result =
          await ExcelExportService.instance.exportAndSave(selected);
      if (mounted) {
        setState(() => _message =
            '${result.message}\n파일: ${result.fileName}');
      }
    } catch (error) {
      if (mounted) setState(() => _message = '다운로드 실패: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('엑셀 화물 다운로드'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                'DB에 저장된 화물의 운송 경로/연도/항차를 선택해 Excel을 생성합니다.\n항차별 변경 폼이 있으면 그 폼을 우선 사용하고, 없으면 운송 경로별 기본 폼을 사용합니다.',
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_batches.isNotEmpty)
                DropdownButtonFormField<ExcelExportBatch>(
                  initialValue: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로 / 연도 / 항차',
                    border: OutlineInputBorder(),
                  ),
                  items: _batches
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            '${e.displayLabel} · ${e.templateLabel}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _exporting
                      ? null
                      : (value) => setState(() => _selected = value),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed:
                    _selected == null || _exporting ? null : _export,
                icon: const Icon(Icons.download_outlined),
                label: Text(_exporting ? 'Excel 생성 중...' : '최신 Excel 생성 및 저장'),
              ),
              const SizedBox(height: 18),
              Text(
                _message,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              const Text(
                '1차 안전 모드',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '기본 폼과 항차별 변경 폼은 DB(Storage)에 보관합니다. 현재 자동 데이터 반영은 "물품 입고 내역" 형식부터 지원하며, 다른 노선 원장/거래명세서 자동 반영은 노선별 구조를 검증하면서 이어서 적용합니다.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
