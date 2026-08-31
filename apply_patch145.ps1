$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText((Resolve-Path $Path), [System.Text.UTF8Encoding]::new($false))
}
function Write-Utf8([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText((Resolve-Path $Path), $Text, [System.Text.UTF8Encoding]::new($false))
}

$quotePath = "lib\screens\quote_request_screen.dart"
$cargoPath = "lib\screens\cargo_management_screen.dart"

if (!(Test-Path $quotePath)) { throw "파일 없음: $quotePath" }
if (!(Test-Path $cargoPath)) { throw "파일 없음: $cargoPath" }

# 1) quote_request_screen.dart:
# _addBox 다음부터 _removeBox 직전까지를 통째로 정확한 함수로 교체.
# Patch144에서 깨진 문자열/함수 조각이 남아 있어도 이 범위 안이면 제거됨.
$q = Read-Utf8 $quotePath

$startAnchor = "  void _addBox() => setState(() {"
$start = $q.IndexOf($startAnchor)
if ($start -lt 0) { throw "안전 중단: _addBox 시작점을 찾지 못했습니다." }

$removeAnchor = "  void _removeBox(int i) {"
$remove = $q.IndexOf($removeAnchor, $start)
if ($remove -lt 0) { throw "안전 중단: _removeBox 시작점을 찾지 못했습니다." }

$addBoxEndNeedle = "      });"
$addBoxEnd = $q.IndexOf($addBoxEndNeedle, $start)
if ($addBoxEnd -lt 0 -or $addBoxEnd -gt $remove) {
    throw "안전 중단: _addBox 종료점을 찾지 못했습니다."
}
$addBoxEnd += $addBoxEndNeedle.Length

$extraFunction = @'

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
                labelText: '비용 이름',
                hintText: '예: 통관비, 기타 수수료',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: '금액 (USD)',
                prefixText: '\$ ',
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
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text.trim());
              if (name.isEmpty || amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('비용 이름과 올바른 USD 금액을 입력해 주세요.')),
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

    if (added == true && mounted) {
      final name = nameController.text.trim();
      final amount = double.tryParse(amountController.text.trim());
      if (name.isNotEmpty && amount != null && amount > 0) {
        setState(() {
          _extraCosts.add(
            ExtraCostItem(name: name, amountUsd: amount),
          );
        });
      }
    }

    nameController.dispose();
    amountController.dispose();
  }

'@

$q = $q.Substring(0, $addBoxEnd) + $extraFunction + $q.Substring($remove)

# Dart const 문자열 안의 literal $는 반드시 escape.
$q = $q.Replace("'기타 비용 추가 (+$)'", "'기타 비용 추가 (+\$)'")
Write-Utf8 $quotePath $q

# 2) cargo_management_screen.dart:
# UI 문구의 literal $만 수정. 구조/기능은 건드리지 않음.
$c = Read-Utf8 $cargoPath
$c = $c.Replace("'기타 비용 (+$)'", "'기타 비용 (+\$)'")
Write-Utf8 $cargoPath $c

Write-Host ""
Write-Host "Patch145 적용 완료"
Write-Host "수정 파일:"
Write-Host " - $quotePath"
Write-Host " - $cargoPath"
Write-Host ""
Write-Host "다음 실행: flutter analyze"
