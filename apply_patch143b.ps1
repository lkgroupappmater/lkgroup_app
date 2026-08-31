$ErrorActionPreference = "Stop"

function Replace-RegexOnce([string]$src,[string]$pattern,[string]$replacement,[string]$label) {
  $m = [regex]::Matches($src,$pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)
  if ($m.Count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$($m.Count)" }
  return [regex]::Replace($src,$pattern,$replacement,[System.Text.RegularExpressions.RegexOptions]::Multiline)
}

# Patch143이 중간 중단된 상태에서 이어서 적용하는 복구 패치입니다.
# cargo_management_screen.dart는 이미 적용됐으므로 다시 건드리지 않습니다.

# ------------------------------------------------------------
# 1) quote_request_screen.dart - 실패 지점부터 계속
# ------------------------------------------------------------
$path="lib/screens/quote_request_screen.dart"
$src=Get-Content $path -Raw -Encoding UTF8

# preview args: 줄바꿈 형식(CRLF/LF)에 영향받지 않게 처리
if ($src -notmatch 'extraCosts:\s*List<ExtraCostItem>') {
  $src=Replace-RegexOnce $src `
    '(?m)^(\s*rates:\s*rates,\s*)$' `
    '$1`r`n        extraCosts: List<ExtraCostItem>.unmodifiable(_extraCosts),' `
    'quote preview args'
}

# 박스 추가 버튼 뒤 기타 비용 버튼
if ($src -notmatch "label:\s*const Text\('기타 비용 추가 \(\+\$\)'") {
  $needle="label: const Text('박스 추가', style: TextStyle(fontSize: 13)),"
  $idx=$src.IndexOf($needle)
  if ($idx -lt 0) { throw "안전 중단 [quote button]: 박스 추가 버튼 없음" }

  # 해당 OutlinedButton의 닫는 괄호를 괄호 깊이로 안전하게 탐색
  $buttonStart=$src.LastIndexOf("OutlinedButton.icon(", $idx)
  if ($buttonStart -lt 0) { throw "안전 중단 [quote button]: 시작점 없음" }
  $depth=0; $end=-1
  for($i=$buttonStart;$i -lt $src.Length-1;$i++){
    if($src[$i] -eq '('){$depth++}
    elseif($src[$i] -eq ')'){
      $depth--
      if($depth -eq 0){
        $semi=$src.IndexOf(';',$i)
        # Widget list에서는 ), 이므로 다음 comma까지 포함
        $comma=$src.IndexOf(',',$i)
        if($comma -ge 0 -and ($semi -lt 0 -or $comma -lt $semi)){ $end=$comma+1 } else { $end=$i+1 }
        break
      }
    }
  }
  if($end -lt 0){throw "안전 중단 [quote button]: 끝점 없음"}

  $insert=@'

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addQuoteExtraCost,
            icon: const Icon(Icons.add_card_outlined, size: 18),
            label: const Text('기타 비용 추가 (+$)',
                style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navyPrimary,
              side: const BorderSide(color: AppColors.navyPrimary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          if (_extraCosts.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._extraCosts.asMap().entries.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('\$${entry.value.amountUsd.toStringAsFixed(2)}'),
                    IconButton(
                      tooltip: '삭제',
                      onPressed: () =>
                          setState(() => _extraCosts.removeAt(entry.key)),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
'@
  $src=$src.Insert($end,$insert)
}
Set-Content $path $src -Encoding UTF8

# ------------------------------------------------------------
# 2) quotation_preview_dialog.dart
# ------------------------------------------------------------
$path="lib/screens/quotation_preview_dialog.dart"
$src=Get-Content $path -Raw -Encoding UTF8

if($src -notmatch "receipt_extra_cost_service.dart"){
  $src=Replace-RegexOnce $src `
    "(?m)^(import '../services/quote_freight_calculator\.dart';\s*)$" `
    '$1`r`nimport ''../services/receipt_extra_cost_service.dart'';' `
    'quotation import'
}
if($src -notmatch 'final List<ExtraCostItem> extraCosts;'){
  $src=Replace-RegexOnce $src `
    '(?m)^(\s*required this\.rates,\s*)$' `
    '$1`r`n    this.extraCosts = const <ExtraCostItem>[],' `
    'quotation ctor'
  $src=Replace-RegexOnce $src `
    '(?m)^(\s*final ExchangeRateSettings rates;\s*)$' `
    '$1`r`n  final List<ExtraCostItem> extraCosts;' `
    'quotation field'
  $src=Replace-RegexOnce $src `
    '(?m)^(\s*rates:\s*widget\.rates,\s*)$' `
    '$1`r`n        extraCosts: widget.extraCosts,' `
    'quotation painter call'
  # 두 번째 required this.rates (painter ctor)
  $matches=[regex]::Matches($src,'(?m)^(\s*required this\.rates,\s*)$')
  if($matches.Count -ne 1){throw "안전 중단 [quotation painter ctor]: 대상=$($matches.Count)"}
  $src=[regex]::Replace($src,'(?m)^(\s*required this\.rates,\s*)$','$1`r`n    required this.extraCosts,',1)
  # painter field: 이제 ExchangeRateSettings rates가 2개여야 함. 마지막 것에 필드 삽입
  $pat='(?m)^(\s*final ExchangeRateSettings rates;\s*)$'
  $ms=[regex]::Matches($src,$pat)
  if($ms.Count -ne 2){throw "안전 중단 [quotation painter field]: 대상=$($ms.Count)"}
  $m=$ms[1]
  $src=$src.Insert($m.Index+$m.Length,"`r`n  final List<ExtraCostItem> extraCosts;")
}

if($src -notmatch 'final extraTotal = extraCosts\.fold'){
  $src=Replace-RegexOnce $src `
    '(?m)^(\s*final usd = result\.totalUsd;\s*)$' `
    '    final extraTotal = extraCosts.fold<double>(0, (sum, e) => sum + e.amountUsd);`r`n    final extraNames = extraCosts.map((e) => e.name).where((e) => e.isNotEmpty).join('', '');`r`n    final usd = result.totalUsd + extraTotal;' `
    'quotation total'
  $src=Replace-RegexOnce $src `
    "(?m)^\s*_text\(c, '특별할인', Rect\.fromLTWH\(totalX \+ 12, sumTop \+ 34, totalW \* \.46, adjH\), 16, bold: true\);\s*\r?\n\s*_text\(c, '-', Rect\.fromLTWH\(totalX \+ totalW \* \.52, sumTop \+ 34, totalW \* \.44, adjH\), 16, bold: true, right: true\);" `
    "    _text(c, extraNames.isEmpty ? '기타 비용' : '기타 비용 (`$extraNames)', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);`r`n    _text(c, extraTotal > 0 ? '+`$`{MoneyFormat.usd(extraTotal)}`' : '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);" `
    'quotation extra row'
}
Set-Content $path $src -Encoding UTF8

Write-Host "Patch143b 복구 적용 완료"
Write-Host "이제 flutter analyze 를 먼저 실행해 주세요."
