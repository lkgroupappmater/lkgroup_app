import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/excel_import_service.dart';

class ExcelUploadScreen extends StatefulWidget {
  const ExcelUploadScreen({super.key});
  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  bool _busy = false;
  String _message =
      '현재 LK Group Excel의 "물품 입고 내역" 시트를 그대로 읽습니다.\n파일명 예: KR_LA_SEA_2026_V01_SHIPMENTS.xlsx';

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final result = await ExcelImportService.instance.pickAndImport();
      if (mounted) {
        setState(() => _message =
            '${result.message}\n화물 반영: ${result.inserted}건 · 제외: ${result.skipped}건 · 고객 할인규칙: ${result.customerRules}건');
      }
    } catch (error) {
      if (mounted) setState(() => _message = '업로드 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('엑셀 화물 업로드'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('관리자·직원·협력/파트너사 전용',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 10),
              const Text(
                '현재 Excel 컬럼을 그대로 인식합니다: No., 송장 번호, 발신인, 수신인, 전화번호, 내용물, 포장형태, 수량, 중량(KGS), L, w, H, 영수 번호, 구획, 비고.\n송장번호가 없어도 Box No.와 실제 자료가 있으면 등록됩니다.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: Text(_busy ? '처리 중...' : '엑셀 파일 선택 및 업데이트'),
              ),
              const SizedBox(height: 18),
              Text(_message,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}
