$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) {
  return Get-Content -Raw -Encoding UTF8 $Path
}

function Write-Utf8([string]$Path, [string]$Text) {
  Set-Content -Path $Path -Value $Text -Encoding UTF8
}

function Ensure-TextSignature([string]$Path, [string]$Label) {
  $src = Read-Utf8 $Path

  # Already patched
  if ($src.Contains("int maxLines = 3, double lineHeight = 1.15")) {
    if ($src.Contains("height: 1.15,")) {
      $src = $src.Replace("height: 1.15,", "height: lineHeight,")
      Write-Utf8 $Path $src
    }
    return
  }

  $pattern = "int maxLines = 3\}\)"
  if ($src -match $pattern) {
    $src = [regex]::Replace(
      $src,
      "int maxLines = 3\}\)",
      "int maxLines = 3, double lineHeight = 1.15})",
      1
    )
    $src = $src.Replace("height: 1.15,", "height: lineHeight,")
    Write-Utf8 $Path $src
    Write-Host "수정 완료: $Label _text lineHeight 지원"
    return
  }

  throw "$Label : _text 함수 시그니처를 찾지 못했습니다."
}

function Patch-AccountBlock([string]$Path, [string]$Label) {
  $src = Read-Utf8 $Path

  # lineHeight already present on KRW account block => done
  if ($src -match "571-22-0330221\\n박성호'[\s\S]{0,220}lineHeight:\s*1\.35") {
    Write-Host "확인: $Label 한국계좌 줄간격 이미 반영됨"
    return
  }

  # Find only the KRW account _text(...) block, regardless of whitespace/formatting
  $pattern = "(?s)(_text\(\s*c,\s*'한국 원화 계좌:\\n경남은행\\n571-22-0330221\\n박성호',.*?maxLines:\s*4,)(\s*\);)"
  $m = [regex]::Match($src, $pattern)
  if (!$m.Success) {
    throw "$Label : 한국계좌 출력부를 찾지 못했습니다. 현재 파일 내용을 보존한 채 중단합니다."
  }

  $replacement = $m.Groups[1].Value + "`r`n      lineHeight: 1.35," + $m.Groups[2].Value
  $src = $src.Substring(0, $m.Index) + $replacement + $src.Substring($m.Index + $m.Length)
  Write-Utf8 $Path $src
  Write-Host "수정 완료: $Label 한국계좌 줄간격 확대"
}

function Patch-Stamp([string]$Path, [string]$Label) {
  $src = Read-Utf8 $Path
  $target = "_imageContain(c, stamp, Rect.fromLTWH(8, signTop + 4, signW - 16, signH - 8));"

  if ($src.Contains($target)) {
    Write-Host "확인: $Label 도장 확대 이미 반영됨"
    return
  }

  $old = "_imageContainTrimmed(c, stamp, Rect.fromLTWH(8, signTop + 27, signW - 16, signH - 29), trimRatio: .18);"
  if ($src.Contains($old)) {
    $src = $src.Replace($old, $target)
    Write-Utf8 $Path $src
    Write-Host "수정 완료: $Label 도장 전체 최대 확대"
    return
  }

  throw "$Label : 도장 출력 코드를 찾지 못했습니다."
}

function Patch-Zone([string]$Path) {
  $src = Read-Utf8 $Path
  if ($src.Contains("_s(rows.first['unloading_zone'])")) {
    Write-Host "확인: 명세서 Zone 실제 필드 이미 반영됨"
    return
  }
  if ($src.Contains("_s(rows.first['zone'])")) {
    $src = $src.Replace("_s(rows.first['zone'])", "_s(rows.first['unloading_zone'])")
    Write-Utf8 $Path $src
    Write-Host "수정 완료: 명세서 상단 Zone 실제 필드 연결"
    return
  }
  throw "명세서 Zone 출력부를 찾지 못했습니다."
}

$project = (Get-Location).Path
$q = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
$s = Join-Path $project "lib\screens\statement_preview_dialog.dart"

if (!(Test-Path $q)) { throw "파일 없음: $q" }
if (!(Test-Path $s)) { throw "파일 없음: $s" }

Copy-Item $q "$q.bak_before_patch115b" -Force
Copy-Item $s "$s.bak_before_patch115b" -Force

Patch-Stamp $q "가견적서"
Ensure-TextSignature $q "가견적서"
Patch-AccountBlock $q "가견적서"

Patch-Zone $s
Patch-Stamp $s "명세서"
Ensure-TextSignature $s "명세서"
Patch-AccountBlock $s "명세서"

# Stamp asset
$stampSource = Join-Path $PSScriptRoot "assets\images\company_stamp.png"
$stampTarget = Join-Path $project "assets\images\company_stamp.png"
if (Test-Path $stampSource) {
  Copy-Item $stampSource $stampTarget -Force
  Write-Host "수정 완료: company_stamp.png 원본 반영"
}

Write-Host ""
Write-Host "Patch115b 문서 수정 완료"
Write-Host "- 이전 Patch115가 중간까지 적용된 상태에서도 재실행 가능"
Write-Host "- SQL 실행 없음"
