$ErrorActionPreference = 'Stop'

function Read-Utf8([string]$path) { Get-Content $path -Raw -Encoding UTF8 }
function Write-Utf8([string]$path,[string]$text) { Set-Content $path $text -Encoding UTF8 }

# 1) cargo_management_screen.dart: Dart 문자열의 bare $만 수정
$path = 'lib/screens/cargo_management_screen.dart'
$src = Read-Utf8 $path
$src = $src.Replace("'기타 비용 (+$)'", "'기타 비용 (+\$)'")
Write-Utf8 $path $src

# 2) quote_request_screen.dart: bare $ 수정 + 누락된 기타비용 입력 함수 추가
$path = 'lib/screens/quote_request_screen.dart'
$src = Read-Utf8 $path
$src = $src.Replace("'기타 비용 추가 (+$)'", "'기타 비용 추가 (+\$)'")

if ($src -notmatch 'Future<void> _addQuoteExtraCost\(\)') {
$method = @'

  Future<void> _addQuoteExtraCost() async {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기타 비용 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '비용명',
                hintText: '예: 통관비, 추가 배송비',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: '금액 (USD)',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim());
              if (name.isEmpty || amount == null || amount <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('비용명과 0보다 큰 USD 금액을 입력해 주세요.')),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (added == true) {
      final amount = double.tryParse(amountController.text.trim());
      if (amount != null && amount > 0 && mounted) {
        setState(() {
          _extraCosts.add(
            ExtraCostItem(
              name: nameController.text.trim(),
              amountUsd: amount,
            ),
          );
        });
      }
    }
    nameController.dispose();
    amountController.dispose();
  }
'@
  $anchor = '  Future<void> _loadSpecialQuotes() async {'
  $idx = $src.IndexOf($anchor)
  if ($idx -lt 0) { throw 'quote_request_screen.dart: _loadSpecialQuotes 기준점을 찾지 못했습니다.' }
  $src = $src.Insert($idx, $method + [Environment]::NewLine)
}
Write-Utf8 $path $src

# 3) statement_preview_dialog.dart: finalUsd 선언을 합계 사용보다 앞으로 이동
$path = 'lib/screens/statement_preview_dialog.dart'
$src = Read-Utf8 $path
$decl = "    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);`r`n    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');`r`n    final finalUsd = freight.totalUsd + extraTotal;`r`n"
# 줄바꿈 형식과 무관하게 기존 선언 1세트를 제거
$src = [regex]::Replace($src, "(?m)^\s*final extraTotal = extraCosts\.fold<double>\(0, \(sum, e\) => sum \+ e\.amountUsd\);\r?\n\s*final extraNames = extraCosts\.map\(\(e\) => e\.name\)\.where\(\(e\) => e\.isNotEmpty\)\.join\(', '\);\r?\n\s*final finalUsd = freight\.totalUsd \+ extraTotal;\r?\n", '', 1)
$anchor = "    final summaryValues = <int, String>{"
$idx = $src.IndexOf($anchor)
if ($idx -lt 0) { throw 'statement_preview_dialog.dart: summaryValues 기준점을 찾지 못했습니다.' }
$src = $src.Insert($idx, $decl)
Write-Utf8 $path $src

Write-Host 'Patch144 적용 완료'
Write-Host '다음 실행: flutter analyze'
