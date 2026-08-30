$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
  return Get-Content -Raw -Encoding UTF8 $Path
}
function Write-Utf8([string]$Path, [string]$Text) {
  Set-Content -Path $Path -Value $Text -Encoding UTF8
}
function Replace-Required([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  if (!$Text.Contains($Old)) {
    throw "Patch119 중단: '$Label' 기준 코드를 찾지 못했습니다. 기존 정상 기능은 수정하지 않았습니다."
  }
  return $Text.Replace($Old, $New)
}

$project = (Get-Location).Path

# 1) Google Maps icon asset
$assetDir = Join-Path $project "assets\images"
if (!(Test-Path $assetDir)) {
  New-Item -ItemType Directory -Path $assetDir -Force | Out-Null
}
Copy-Item (Join-Path $PSScriptRoot "assets\images\google_maps_icon.png") `
          (Join-Path $assetDir "google_maps_icon.png") -Force
Write-Host "복사 완료: Google Maps 아이콘"

# 2) pubspec asset registration
$pubspec = Join-Path $project "pubspec.yaml"
Copy-Item $pubspec "$pubspec.bak_before_patch119" -Force
$src = Read-Utf8 $pubspec

if (!$src.Contains("assets/images/google_maps_icon.png")) {
  $needle = "    - assets/images/payment_qr_usd.png"
  $replacement = "    - assets/images/payment_qr_usd.png`r`n    - assets/images/google_maps_icon.png"
  $src = Replace-Required $src $needle $replacement "pubspec Google Maps asset 등록"
}
Write-Utf8 $pubspec $src

# 3) Dashboard Google Maps logo -> user-provided icon image
$dashboard = Join-Path $project "lib\screens\dashboard_home_screen.dart"
Copy-Item $dashboard "$dashboard.bak_before_patch119" -Force
$src = Read-Utf8 $dashboard

$old = @'
      case 'google_maps':
        return Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.location_on_rounded,
            size: 19,
            color: Color(0xFF4285F4),
          ),
        );
'@
$new = @'
      case 'google_maps':
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/images/google_maps_icon.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        );
'@
$src = Replace-Required $src $old $new "Google Maps 아이콘 이미지 교체"
Write-Utf8 $dashboard $src

Write-Host ""
Write-Host "Patch119 적용 완료"
Write-Host "- Google Maps 아이콘을 첨부 이미지로 교체"
Write-Host "- 지도 링크/타이틀/기존 홈 기능은 변경 없음"
Write-Host "- 화물 삭제 DB 로직은 변경 없음"
Write-Host "- SQL 없음"
