$ErrorActionPreference = 'Stop'

$path = "lib/screens/quote_request_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$text = Get-Content -Raw -Encoding UTF8 $path

# 1) import 추가
$needleImport = "import '../services/quote_service.dart';"
$replacementImport = @"
import '../services/quote_service.dart';
import 'quotation_preview_dialog.dart';
"@
if ($text -notmatch [regex]::Escape("import 'quotation_preview_dialog.dart';")) {
  if (!$text.Contains($needleImport)) { throw "quote_service import 위치를 찾지 못했습니다." }
  $text = $text.Replace($needleImport, $replacementImport.TrimEnd())
}

# 2) 견적서 보기 함수 추가
$marker = "  Future<void> _loadSpecialQuotes() async {"
if ($text -notmatch "Future<void> _showQuotationPreview\(\)") {
$method = @'
  Future<void> _showQuotationPreview() async {
    if (!_isLoggedIn) {
      _requireLoginMessage();
      return;
    }

    // 협력/파트너사 권한 제외. DB의 현재 로그인 프로필 역할을 기준으로 재확인합니다.
    if (SupabaseConfig.isConfigured) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();
          if ('${profile?['role'] ?? ''}' == 'partner') {
            _message('협력/파트너사는 견적서 보기 권한이 없습니다.');
            return;
          }
        }
      } catch (error) {
        _message('견적서 권한 확인 실패: $error');
        return;
      }
    }

    if (_calculation == null || _calculationRates == null) {
      await _calculateFreight();
    }
    final calculation = _calculation;
    final rates = _calculationRates;
    if (calculation == null || rates == null || !mounted) return;

    final previewBoxes = <QuotationPreviewBox>[];
    for (final line in calculation.lines) {
      final sourceIndex = line.index - 1;
      if (sourceIndex < 0 || sourceIndex >= _boxes.length) continue;
      final source = _boxes[sourceIndex];
      previewBoxes.add(
        QuotationPreviewBox(
          index: line.index,
          weightKg: double.tryParse(source.weight) ?? 0,
          lengthCm: double.tryParse(source.length) ?? 0,
          widthCm: double.tryParse(source.width) ?? 0,
          heightCm: double.tryParse(source.height) ?? 0,
          quantity: int.tryParse(source.quantity) ?? 1,
          result: line,
        ),
      );
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuotationPreviewDialog(
        routeLabel: _selectedRoute,
        boxes: previewBoxes,
        result: calculation,
        rates: rates,
      ),
    );
  }

'@
  if (!$text.Contains($marker)) { throw "_loadSpecialQuotes 위치를 찾지 못했습니다." }
  $text = $text.Replace($marker, $method + $marker)
}

# 3) 단일 운임 확인 버튼을 2개 버튼 Row로 교체
$old = @'
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _calculateFreight,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navyPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                '운임 확인',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
'@

$new = @'
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _calculateFreight,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyPrimary,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '운임 확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _showQuotationPreview,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text(
                      '견적서 보기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyPrimary,
                      side: const BorderSide(color: AppColors.navyPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
'@

if (!$text.Contains($old)) {
  throw "운임 확인 버튼 원본 블록을 찾지 못했습니다. 현재 master와 패치 기준이 달라졌을 수 있습니다."
}
$text = $text.Replace($old, $new)

Set-Content -Path $path -Value $text -Encoding UTF8
Write-Host "PHASE 2 quote_request_screen.dart 패치 완료"
