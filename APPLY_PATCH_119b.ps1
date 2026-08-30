$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
  return Get-Content -Raw -Encoding UTF8 $Path
}
function Write-Utf8([string]$Path, [string]$Text) {
  Set-Content -Path $Path -Value $Text -Encoding UTF8
}

$project = (Get-Location).Path

# 1) icon copy only when source/target are different
$iconSource = Join-Path $PSScriptRoot "assets\images\google_maps_icon.png"
$iconTarget = Join-Path $project "assets\images\google_maps_icon.png"
if (([System.IO.Path]::GetFullPath($iconSource)) -ne ([System.IO.Path]::GetFullPath($iconTarget))) {
  Copy-Item $iconSource $iconTarget -Force
  Write-Host "복사 완료: Google Maps 아이콘"
} else {
  Write-Host "확인: Google Maps 아이콘 이미 프로젝트 위치에 있음"
}

# 2) pubspec asset line: add only when absent
$pubspec = Join-Path $project "pubspec.yaml"
Copy-Item $pubspec "$pubspec.bak_before_patch119b" -Force
$src = Read-Utf8 $pubspec
if (!$src.Contains("assets/images/google_maps_icon.png")) {
  $needle = "    - assets/images/payment_qr_usd.png"
  if (!$src.Contains($needle)) {
    throw "Patch119b 중단: pubspec asset 기준 줄을 찾지 못했습니다."
  }
  $src = $src.Replace(
    $needle,
    $needle + "`r`n    - assets/images/google_maps_icon.png"
  )
  Write-Utf8 $pubspec $src
  Write-Host "추가 완료: pubspec Google Maps asset"
} else {
  Write-Host "확인: pubspec Google Maps asset 이미 등록됨"
}

# 3) dashboard icon: handle either old Material icon or already-updated image state
$dashboard = Join-Path $project "lib\screens\dashboard_home_screen.dart"
Copy-Item $dashboard "$dashboard.bak_before_patch119b" -Force
$src = Read-Utf8 $dashboard

if ($src.Contains("'assets/images/google_maps_icon.png'")) {
  Write-Host "확인: 홈 Google Maps 이미지 아이콘 이미 적용됨"
} else {
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
  if (!$src.Contains($old)) {
    throw "Patch119b 중단: 홈 Google Maps 기존 아이콘 코드를 찾지 못했습니다."
  }
  $src = $src.Replace($old, $new)
  Write-Utf8 $dashboard $src
  Write-Host "수정 완료: 홈 Google Maps 아이콘 이미지"
}

Write-Host ""
Write-Host "Patch119b 적용 완료"
Write-Host "- 자기 자신 복사 방지"
Write-Host "- pubspec 중복 asset 등록 방지"
Write-Host "- 기존 지도 링크/삭제 기능/DB 변경 없음"
Write-Host "- SQL 없음"
