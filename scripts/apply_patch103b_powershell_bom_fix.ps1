$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$targets = @(
  (Join-Path $project 'scripts\apply_patch102_digital_forms.ps1')
)

foreach ($path in $targets) {
  if (-not (Test-Path $path)) {
    throw "파일을 찾을 수 없습니다: $path"
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    [System.IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length - 1)])
    Write-Host "UTF-8 BOM 제거 완료: $path" -ForegroundColor Green
  } else {
    Write-Host "BOM 없음 / 수정 불필요: $path" -ForegroundColor Yellow
  }
}

Write-Host ''
Write-Host '이제 다시 실행하세요:' -ForegroundColor Cyan
Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\apply_patch102_digital_forms.ps1'
