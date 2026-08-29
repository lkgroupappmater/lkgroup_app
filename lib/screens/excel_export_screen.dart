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
  String? _route;
  int? _year;
  String? _voyage;

  List<String> get _routes => _batches.map((e) => e.routeLabel).toSet().toList()..sort();
  List<int> get _years {
    final v = _batches.where((e) => e.routeLabel == _route).map((e) => e.year).toSet().toList();
    v.sort((a,b) => b.compareTo(a)); return v;
  }
  List<String> get _voyages {
    final v = _batches.where((e) => e.routeLabel == _route && e.year == _year)
        .map((e) => e.voyage).toSet().toList();
    v.sort((a,b) => b.compareTo(a)); return v;
  }
  ExcelExportBatch? get _selected {
    if (_route == null || _year == null || _voyage == null) return null;
    for (final b in _batches) {
      if (b.routeLabel == _route && b.year == _year && b.voyage == _voyage) return b;
    }
    return null;
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _message = ''; });
    try {
      final batches = await ExcelExportService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _batches = batches; _route = null; _year = null; _voyage = null;
        _message = batches.isEmpty
            ? '실제 화물 데이터가 등록된 운송 경로/년도/항차가 없습니다.'
            : '실제 화물 데이터가 1건 이상 있는 운송 경로/년도/항차만 선택할 수 있습니다.';
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
    setState(() { _exporting = true; _message = '원본 Excel 모양을 유지하면서 최신 자료를 반영 중입니다...'; });
    try {
      final result = await ExcelExportService.instance.exportAndSave(selected);
      if (mounted) setState(() => _message = '${result.message}\n파일: ${result.fileName}');
    } catch (error) {
      if (mounted) setState(() => _message = '다운로드 실패: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  InputDecoration _dec(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('화물 데이타 엑셀 다운로드'),
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
    ),
    backgroundColor: AppColors.background,
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('관리자·직원·협력/파트너사 전용',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const SizedBox(height: 10),
        const Text('실제 화물 데이터가 하나라도 등록된 운송 경로/년도/항차만 표시합니다.'),
        const SizedBox(height: 20),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_batches.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _route, isExpanded: true, decoration: _dec('운송 경로'),
            items: _routes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: _exporting ? null : (v) => setState(() { _route=v; _year=null; _voyage=null; }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            key: ValueKey('year-$_route'), initialValue: _year, decoration: _dec('년도'),
            items: _years.map((v) => DropdownMenuItem(value: v, child: Text('$v년'))).toList(),
            onChanged: _route == null || _exporting ? null : (v) => setState(() { _year=v; _voyage=null; }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('voyage-$_route-$_year'), initialValue: _voyage, decoration: _dec('항차'),
            items: _voyages.map((v) => DropdownMenuItem(value: v, child: Text(v.endsWith('항차') ? v : '$v항차'))).toList(),
            onChanged: _year == null || _exporting ? null : (v) => setState(() => _voyage=v),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _selected == null || _exporting ? null : _export,
          icon: const Icon(Icons.download_outlined),
          label: Text(_exporting ? 'Excel 생성 중...' : '최신 Excel 생성 및 저장'),
        ),
        const SizedBox(height: 18),
        Text(_message, style: const TextStyle(color: AppColors.textSecondary)),
      ]),
    ),
  );
}
