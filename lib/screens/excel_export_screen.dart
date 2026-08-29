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
  List<ExcelTemplateBatch> _templates = const [];
  ExcelTemplateBatch? _selected;

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
      final templates = await ExcelExportService.instance.listTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _selected = templates.isEmpty ? null : templates.first;
        _message = templates.isEmpty
            ? '먼저 해당 항차의 실제 Excel 파일을 "엑셀 화물 업로드"에서 한 번 업로드해 주세요.'
            : '다운로드할 항차를 선택해 주세요.';
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
                '관리자·직원 전용',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '업로드했던 실제 Excel 파일을 원본 템플릿으로 보관하고, 다운로드 시점의 최신 화물 DB 자료를 복사본에 반영합니다.\n원본 파일 자체는 덮어쓰지 않습니다.',
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_templates.isNotEmpty)
                DropdownButtonFormField<ExcelTemplateBatch>(
                  value: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로 / 연도 / 항차',
                    border: OutlineInputBorder(),
                  ),
                  items: _templates
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e.displayLabel,
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
                '현재 단계에서는 실제 "물품 입고 내역" 시트의 화물 행만 DB 최신값으로 교체합니다. 다른 시트, 셀 서식, 수식, 병합, 그림, 인쇄설정은 새로 만들지 않고 원본 XLSX 내부 파일을 그대로 보존합니다.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
