from pathlib import Path
import shutil

cwd = Path.cwd()
stray = cwd / "unloading_list_management_screen.dart"
target = cwd / "lib" / "screens" / "unloading_list_management_screen.dart"

# Patch174A 압축의 보조 원본 Dart가 프로젝트 최상위에 남아
# flutter analyze가 이를 별도 Dart 파일로 분석하면서 ../core, ../services 경로가 깨졌습니다.
# 실제 앱 파일은 lib/screens 아래에 있어야 합니다.
if stray.exists():
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(stray, target)
    stray.unlink()
    print("프로젝트 최상위의 stray unloading_list_management_screen.dart 제거 완료.")
else:
    print("프로젝트 최상위 stray 파일 없음.")

if not target.exists():
    raise SystemExit(
        "lib/screens/unloading_list_management_screen.dart 가 없습니다. "
        "Patch174A를 먼저 적용한 뒤 이 FIX를 실행하세요."
    )

# 혹시 이전 압축을 풀며 프로젝트 최상위에 남은 patch helper Dart가 더 있는지
# 이름이 명확한 Patch174A 파일만 정리합니다. 실제 lib/ 소스는 건드리지 않습니다.
for name in ("PATCH174A_apply.py",):
    # Python helper는 analyze 대상이 아니므로 유지해도 되지만 정리하지 않습니다.
    pass

print("Patch174A FIX 완료.")
