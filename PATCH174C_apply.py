from pathlib import Path
import shutil

cwd = Path.cwd()
export_dst = cwd / 'lib' / 'screens' / 'excel_export_screen.dart'
unload_dst = cwd / 'lib' / 'screens' / 'unloading_list_management_screen.dart'

if not export_dst.exists():
    raise SystemExit('lib/screens/excel_export_screen.dart not found')
if not unload_dst.exists():
    raise SystemExit('lib/screens/unloading_list_management_screen.dart not found - Patch174A 먼저 적용 필요')

shutil.copy2(cwd / 'excel_export_screen.dart', export_dst)
shutil.copy2(cwd / 'unloading_list_management_screen.dart', unload_dst)

# 압축 원본 Dart는 프로젝트 최상위에 남기지 않음: flutter analyze stray 오류 방지.
(cwd / 'excel_export_screen.dart').unlink(missing_ok=True)
(cwd / 'unloading_list_management_screen.dart').unlink(missing_ok=True)

print('Patch174C Dart 적용 완료')
