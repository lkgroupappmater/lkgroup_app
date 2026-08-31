$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$p = Join-Path $root "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $p)) { throw "파일 없음: $p" }

Copy-Item $p "$p.bak_before_patch132f" -Force
$s = Get-Content $p -Raw -Encoding UTF8

# 1) Patch132 언어 selector XML 변경만 비활성화.
# Patch129 receipt selector는 유지.
if ($s -match 'function\s+addStatementLanguageSelector\s*\(') {
  if ($s -notmatch 'PATCH132F_LANGUAGE_DISABLED') {
    $s = [regex]::Replace(
      $s,
      '(function\s+addStatementLanguageSelector\s*\([\s\S]*?\)\s*:\s*void\s*\{)',
      '$1' + "`r`n  // PATCH132F_LANGUAGE_DISABLED: Excel sheet XML 복구 팝업 원인 분리용.`r`n  return;",
      1
    )
    Write-Host "[OK] Patch132 언어 dataValidation XML 변경 비활성화" -ForegroundColor Green
  } else {
    Write-Host "[OK] 언어 selector 비활성화가 이미 적용됨" -ForegroundColor Yellow
  }
} else {
  Write-Host "[INFO] addStatementLanguageSelector 함수 없음 - 변경 생략" -ForegroundColor Yellow
}

# 2) TH->LA LAND:
# '물품 입고 내역'이 없는 스팟형은 422로 중단하지 않음.
$old = @'
    const targetPath = workbookSheetPath(files, '물품 입고 내역');
    if (!targetPath || !files[targetPath]) {
      return json(422, {
        error:
          '현재 1차 Export는 \"물품 입고 내역\" 시트가 있는 실제 Excel부터 지원합니다. 원본 템플릿은 안전하게 저장되어 있습니다.',
      });
    }

    const strings = sharedStrings(files);
    const sheetXml = strFromU8(files[targetPath]);
    files[targetPath] = strToU8(
      updateCargoSheet(
        sheetXml,
        strings,
        enrichedShipments,
      ),
    );
'@

$new = @'
    const targetPath = workbookSheetPath(files, '물품 입고 내역');
    const strings = sharedStrings(files);

    if (targetPath && files[targetPath]) {
      const sheetXml = strFromU8(files[targetPath]);
      files[targetPath] = strToU8(
        updateCargoSheet(
          sheetXml,
          strings,
          enrichedShipments,
        ),
      );
    } else if (routeKey !== 'th_la_land') {
      return json(422, {
        error:
          '현재 1차 Export는 \"물품 입고 내역\" 시트가 있는 실제 Excel부터 지원합니다. 원본 템플릿은 안전하게 저장되어 있습니다.',
      });
    }
'@

if ($s.Contains($old)) {
  $s = $s.Replace($old, $new)
  Write-Host "[OK] TH-LA LAND 스팟형 422 예외 적용" -ForegroundColor Green
} elseif ($s -match "else if \(routeKey !== 'th_la_land'\)") {
  Write-Host "[OK] TH-LA LAND 예외가 이미 적용됨" -ForegroundColor Yellow
} else {
  # 공백/개행 차이를 허용한 안전한 fallback
  $pattern = "(?ms)\s{4}const targetPath = workbookSheetPath\(files, '물품 입고 내역'\);\s+if \(!targetPath \|\| !files\[targetPath\]\) \{.*?\s{4}const strings = sharedStrings\(files\);\s+const sheetXml = strFromU8\(files\[targetPath\]\);\s+files\[targetPath\] = strToU8\(\s+updateCargoSheet\(\s+sheetXml,\s+strings,\s+enrichedShipments,\s+\),\s+\);"
  if ([regex]::IsMatch($s, $pattern)) {
    $s = [regex]::Replace($s, $pattern, "`r`n$new", 1)
    Write-Host "[OK] TH-LA LAND 스팟형 422 예외 적용(regex)" -ForegroundColor Green
  } else {
    throw "TH-LA LAND 422 처리 블록을 찾지 못했습니다. index.ts는 저장하지 않았습니다."
  }
}

Set-Content $p $s -Encoding UTF8
Write-Host ""
Write-Host "[OK] Patch132f 적용 완료" -ForegroundColor Green
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "npx supabase functions deploy export-shipment-excel"
