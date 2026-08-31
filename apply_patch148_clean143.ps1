$ErrorActionPreference = "Stop"

$sourceCommit = "5a620c6e1b1a78c6ab202fcb3686fc603ffef8d3"
$files = @(
  "lib/screens/cargo_management_screen.dart",
  "lib/screens/quote_request_screen.dart",
  "lib/screens/quotation_preview_dialog.dart",
  "lib/screens/statement_preview_dialog.dart",
  "lib/services/receipt_extra_cost_service.dart",
  "supabase/089_receipt_extra_costs.sql"
)

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
  throw "현재 폴더가 Git 저장소가 아닙니다."
}

# Patch143 기능이 처음 완성된 알려진 커밋에서 파일 전체를 다시 가져옵니다.
# 이후 알려진 analyzer 오류만 정확하게 고칩니다.
foreach ($file in $files) {
  git cat-file -e "$sourceCommit`:$file" 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "기준 커밋에 파일이 없습니다: $file"
  }

  $dir = Split-Path $file -Parent
  if ($dir -and !(Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $tmp = [System.IO.Path]::GetTempFileName()
  cmd /c "git show $sourceCommit`:$file > `"$tmp`""
  if ($LASTEXITCODE -ne 0) {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw "Git 파일 복원 실패: $file"
  }
  Copy-Item $tmp $file -Force
  Remove-Item $tmp -Force
  Write-Host "기준 파일 복원: $file"
}

$utf8 = [System.Text.UTF8Encoding]::new($false)

function Read-Utf8([string]$Path) {
  return [System.IO.File]::ReadAllText((Resolve-Path $Path), $utf8)
}

function Write-Utf8([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText((Resolve-Path $Path), $Text, $utf8)
}

# -------------------------------------------------------------------
# 1. Cargo: Dart 문자열 안 literal $ 2곳 수정
# -------------------------------------------------------------------
$cargoPath = "lib/screens/cargo_management_screen.dart"
$cargo = Read-Utf8 $cargoPath

$before = $cargo
$cargo = $cargo.Replace("Text('$receipt · 기타 비용 (+$)')", "Text('$receipt · 기타 비용 (+\$)')")
$cargo = $cargo.Replace("tooltip: '기타 비용 (+$)'", "tooltip: '기타 비용 (+\$)'")

if ($cargo -eq $before) {
  throw "안전 중단: cargo 기타비용 문자열 수정 대상을 찾지 못했습니다."
}
Write-Utf8 $cargoPath $cargo

# -------------------------------------------------------------------
# 2. Quote: 누락된 _addQuoteExtraCost 함수 1회 삽입 + literal $ 수정
# -------------------------------------------------------------------
$quotePath = "lib/screens/quote_request_screen.dart"
$quote = Read-Utf8 $quotePath

if ($quote.Contains("Future<void> _addQuoteExtraCost() async")) {
  throw "안전 중단: 기준 quote 파일에 _addQuoteExtraCost가 이미 존재합니다."
}

$anchor = @'
  void _addBox() => setState(() {
        _boxes.add(_BoxEntry());
        _calculation = null;
        _calculationRates = null;
      });

  void _removeBox(int i) {
'@

$method = @'
  void _addBox() => setState(() {
        _boxes.add(_BoxEntry());
        _calculation = null;
        _calculationRates = null;
      });

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
                hintText: '예: 통관비용, 보관료, 기타 수수료',
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
                  const SnackBar(
                    content: Text('비용 이름과 0보다 큰 USD 금액을 입력해 주세요.'),
                  ),
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

  void _removeBox(int i) {
'@

if (!$quote.Contains($anchor)) {
  throw "안전 중단: quote 함수 삽입 기준점을 찾지 못했습니다."
}

$quote = $quote.Replace($anchor, $method)
$quote = $quote.Replace("'기타 비용 추가 (+$)'", "'기타 비용 추가 (+\$)'")
Write-Utf8 $quotePath $quote

# -------------------------------------------------------------------
# 3. Statement: finalUsd 선언을 summary보다 앞으로 이동
# -------------------------------------------------------------------
$statementPath = "lib/screens/statement_preview_dialog.dart"
$statement = Read-Utf8 $statementPath

$summaryAnchor = @'
    final totalVolume = freight.lines.fold<double>(0, (v, f) => v + f.volumeWeight);
    final summaryValues = <int, String>{
'@

$summaryReplacement = @'
    final totalVolume = freight.lines.fold<double>(0, (v, f) => v + f.volumeWeight);
    final extraTotal =
        extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final extraNames =
        extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
    final finalUsd = freight.totalUsd + extraTotal;
    final summaryValues = <int, String>{
'@

if (!$statement.Contains($summaryAnchor)) {
  throw "안전 중단: statement summary 기준점을 찾지 못했습니다."
}
$statement = $statement.Replace($summaryAnchor, $summaryReplacement)

$lateBlock = @'
    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);
    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join(', ');
    final finalUsd = freight.totalUsd + extraTotal;

'@

if (!$statement.Contains($lateBlock)) {
  throw "안전 중단: statement 후반 중복 계산 블록을 찾지 못했습니다."
}
$statement = $statement.Replace($lateBlock, "")
Write-Utf8 $statementPath $statement

Write-Host ""
Write-Host "Patch148 CLEAN143 적용 완료"
Write-Host "- Patch142 이후 요청한 영수번호 그룹 카드"
Write-Host "- 개별 화물 편집/잠금"
Write-Host "- 영수번호별 기타 비용 (+USD)"
Write-Host "- 견적 기타 비용"
Write-Host "- 견적/명세서 최종 합계 반영"
Write-Host "- Batch 명세서 기타 비용 반영"
Write-Host ""
Write-Host "중요: 아직 089 SQL은 실행하지 마세요."
Write-Host "먼저 실행: flutter analyze"
