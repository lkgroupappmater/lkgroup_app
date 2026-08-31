$ErrorActionPreference = "Stop"
$path = "lib/screens/change_approval_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$src = Get-Content $path -Raw -Encoding UTF8
$old = @'
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                '이름은 있으나 연락처가 없어 확인이 필요한 데이터입니다.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
'@
$new = @'
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${row['reason'] ?? '수취인 정보 확인 필요'}',
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
'@

$count = ([regex]::Matches($src, [regex]::Escape($old))).Count
if ($count -ne 1) {
  throw "안전 중단: 대상 문구 블록이 정확히 1개가 아닙니다. 발견: $count"
}
$src = $src.Replace($old, $new)
Set-Content $path $src -Encoding UTF8
Write-Host "Patch141 적용 완료: 불확실 데이터 카드가 DB reason을 표시합니다."
