$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Backup-And-Copy($srcRel, $dstRel) {
  $src = Join-Path $Root $srcRel
  $dst = Join-Path $Root $dstRel
  if (!(Test-Path $src)) { throw "패치 파일 없음: $src" }
  if (Test-Path $dst) { Copy-Item $dst "$dst.bak_before_patch123" -Force }
  $dir = Split-Path $dst -Parent
  if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Copy-Item $src $dst -Force
}

Backup-And-Copy "patch_files\lib\services\customer_benefit_service.dart.txt" "lib\services\customer_benefit_service.dart"
Backup-And-Copy "patch_files\lib\services\freight_service.dart.txt" "lib\services\freight_service.dart"
Backup-And-Copy "patch_files\lib\screens\discount_management_screen.dart.txt" "lib\screens\discount_management_screen.dart"
Backup-And-Copy "patch_files\assets\images\facebook_icon.png" "assets\images\facebook_icon.png"
Backup-And-Copy "patch_files\supabase\068_customer_identity_groups_discount_tiers_badge_fix.sql" "supabase\068_customer_identity_groups_discount_tiers_badge_fix.sql"

# Facebook icon renderer만 최소 변경.
$dash = Join-Path $Root "lib\screens\dashboard_home_screen.dart"
if (!(Test-Path $dash)) { throw "대상 파일 없음: $dash" }
Copy-Item $dash "$dash.bak_before_patch123" -Force
$text = Get-Content $dash -Raw -Encoding UTF8

$old = @'
      case 'facebook':
        return Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF1877F2),
            shape: BoxShape.circle,
          ),
          child: const Text(
            'f',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
'@

$new = @'
      case 'facebook':
        return Image.asset(
          'assets/images/facebook_icon.png',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
        );
'@

if ($text.Contains($old)) {
  $text = $text.Replace($old, $new)
  Set-Content $dash $text -Encoding UTF8
  Write-Host "Facebook 로고 교체 완료"
} elseif ($text -match "assets/images/facebook_icon.png") {
  Write-Host "Facebook 로고는 이미 교체되어 있습니다."
} else {
  Write-Warning "Facebook 기존 블록을 자동으로 찾지 못했습니다. 다른 기능 패치는 계속 적용되었습니다."
}

Write-Host ""
Write-Host "Patch123 파일 적용 완료."
Write-Host "다음 순서:"
Write-Host "1) Supabase SQL Editor: supabase/068_customer_identity_groups_discount_tiers_badge_fix.sql 전체 실행"
Write-Host "2) flutter analyze"
