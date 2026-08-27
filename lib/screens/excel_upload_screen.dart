import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/excel_import_service.dart';

class ExcelUploadScreen extends StatefulWidget {
  const ExcelUploadScreen({super.key});
  @override State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  bool _busy = false;
  String _message = '엑셀 열 이름을 기준으로 화물 데이터를 등록합니다.';

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final result = await ExcelImportService.instance.pickAndImport();
      if (mounted) setState(() => _message = '${result.message}\n등록: ${result.inserted}건 · 제외: ${result.skipped}건');
    } catch (error) {
      if (mounted) setState(() => _message = '업로드 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('엑셀 화물 업로드'), backgroundColor: AppColors.primary, foregroundColor: AppColors.white),
    backgroundColor: AppColors.background,
    body: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('관리자·직원 전용', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
      const SizedBox(height: 10),
      const Text('필수 열: 송장번호 또는 invoice_number. 박스번호, 노선, 수령인, 전화번호, 입고날짜, 무게, 가로, 세로, 높이, 수량도 자동 매핑합니다.'),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file), label: Text(_busy ? '처리 중...' : '엑셀 파일 선택 및 업로드')),
      const SizedBox(height: 18),
      Text(_message, style: const TextStyle(color: AppColors.textSecondary)),
    ])),
  );
}
