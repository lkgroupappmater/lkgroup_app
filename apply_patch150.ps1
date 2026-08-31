$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
  if ($count -ne 1) { throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

$path="lib/screens/cargo_management_screen.dart"
$text=ReadText $path

# 1) 영수번호 그룹 헤더 표시 문구 단순화
$text=ReplaceOnce $text @'
                      Text(
                        '이름/회사명: $name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text('연락처: ${phone.isEmpty ? '-' : phone}',
                          style: const TextStyle(fontSize: 12)),
'@ @'
                      Text(
                        '$name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(phone.isEmpty ? '-' : phone,
                          style: const TextStyle(fontSize: 12)),
'@ "receipt header labels"

# 2) 편집 / 잠금 사이 간격 조금 더 확보
# Patch149에서 오른쪽 세로 배치된 Column 안 두 IconButton 사이에 SizedBox 추가
$text=ReplaceOnce $text @'
                    IconButton(
                      tooltip: '편집',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _selectedIds
                                  ..clear()
                                  ..add(id);
                              });
                              await _editCheckedGroup([item]);
                            },
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                    if (_isAdmin)
                      Container(
'@ @'
                    IconButton(
                      tooltip: '편집',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _selectedIds
                                  ..clear()
                                  ..add(id);
                              });
                              await _editCheckedGroup([item]);
                            },
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                    if (_isAdmin) const SizedBox(height: 8),
                    if (_isAdmin)
                      Container(
'@ "edit lock spacing"

WriteText $path $text

Write-Host ""
Write-Host "Patch150 적용 완료"
Write-Host "- 이름/회사명 라벨 제거 -> 값만 표시"
Write-Host "- 연락처 라벨 제거 -> 값만 표시"
Write-Host "- 영수번호/구획, 총 개수 라벨은 유지"
Write-Host "- 편집/잠금 아이콘 간격 +8px"
Write-Host ""
Write-Host "다음: flutter analyze"
