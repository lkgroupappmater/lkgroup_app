$ErrorActionPreference="Stop"
$baseline="83f2300d3f55f0d488d45e48757a02ab6712e626"
$files=@(
"lib/screens/cargo_management_screen.dart",
"lib/screens/quote_request_screen.dart",
"lib/screens/quotation_preview_dialog.dart",
"lib/screens/statement_preview_dialog.dart"
)
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup="_patch147_backup_$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null

foreach($f in $files){
  if(Test-Path $f){
    $dst=Join-Path $backup $f
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item $f $dst -Force
  }
  git cat-file -e "$baseline`:$f" 2>$null
  if($LASTEXITCODE -ne 0){ throw "기준 커밋에 파일 없음: $f" }
  $tmp=[System.IO.Path]::GetTempFileName()
  cmd /c "git show $baseline`:$f > `"$tmp`""
  if($LASTEXITCODE -ne 0){ throw "복원 실패: $f" }
  Copy-Item $tmp $f -Force
  Remove-Item $tmp -Force
  Write-Host "복원 완료: $f"
}
Write-Host ""
Write-Host "Patch147 기준점 복원 완료"
Write-Host "기준 commit: $baseline"
Write-Host "현재 꼬인 파일 백업: $backup"
Write-Host "다음: flutter analyze"
