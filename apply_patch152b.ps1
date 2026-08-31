$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)
$path = "lib/screens/change_approval_screen.dart"

function ReadText([string]$p) {
  [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8)
}
function WriteText([string]$p,[string]$t) {
  [System.IO.File]::WriteAllText((Resolve-Path $p), $t, $utf8)
}
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

$text = ReadText $path

# 정확히 _incompleteCard 함수 범위만 잘라 수정
$startToken = "  Widget _incompleteCard(Map<String, dynamic> row) {"
$endToken = "  Widget _autoUnmatchedCard(Map<String, dynamic> row) {"
$start = $text.IndexOf($startToken)
$end = $text.IndexOf($endToken)
if ($start -lt 0 -or $end -le $start) {
  throw "안전 중단: _incompleteCard 함수 범위를 찾지 못했습니다."
}

$before = $text.Substring(0, $start)
$section = $text.Substring($start, $end - $start)
$after = $text.Substring($end)

$section = ReplaceOnce $section @'
            Text(
              '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
'@ @'
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${row['box_number'] ?? ''} · ${row['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    OutlinedButton(
                      onPressed: () => _reviewIncomplete(row, lock: false),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      child: const Text(
                        '확인/수정',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _reviewIncomplete(row, lock: true),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      icon: const Icon(Icons.lock_outline, size: 14),
                      label: const Text(
                        '확정/잠금',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
'@ "incomplete top actions"

$section = ReplaceOnce $section @'
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _reviewIncomplete(row, lock: false),
                  child: const Text('확인 / 수정'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => _reviewIncomplete(row, lock: true),
                  icon: const Icon(Icons.lock_outline, size: 17),
                  label: const Text('확정 / 잠금'),
                ),
              ],
            ),
'@ @'
            const SizedBox(height: 4),
'@ "remove incomplete bottom actions"

$text = $before + $section + $after

# 정확히 _requestCard 함수 범위만 잘라 잠금 배지 추가
$startToken2 = "  Widget _requestCard(Map<String, dynamic> r) {"
$endToken2 = "  List<Widget> _editorFields(Map<String, dynamic> r) {"
$start2 = $text.IndexOf($startToken2)
$end2 = $text.IndexOf($endToken2)
if ($start2 -lt 0 -or $end2 -le $start2) {
  throw "안전 중단: _requestCard 함수 범위를 찾지 못했습니다."
}

$before2 = $text.Substring(0, $start2)
$section2 = $text.Substring($start2, $end2 - $start2)
$after2 = $text.Substring($end2)

$section2 = ReplaceOnce $section2 @'
                Expanded(
                  child: Text(
                    '${r['box_number'] ?? ''} · ${r['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
'@ @'
                Expanded(
                  child: Text(
                    '${r['box_number'] ?? ''} · ${r['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (r['data_locked'] == true)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5E5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 13, color: Colors.redAccent),
                        SizedBox(width: 3),
                        Text(
                          '잠금',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
'@ "request lock badge"

$text = $before2 + $section2 + $after2
WriteText $path $text

Write-Host ""
Write-Host "Patch152b 적용 완료"
Write-Host "- cargo_management_screen.dart는 건드리지 않음"
Write-Host "- 불확실 데이터 확인/수정, 확정/잠금 버튼 우측 상단 이동"
Write-Host "- 변경요청 잠긴 화물 빨간 잠금 배지 추가"
Write-Host ""
Write-Host "다음: flutter analyze"
