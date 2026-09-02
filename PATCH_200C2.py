from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: PATCH_200C2.py <project-root>")

    project_root = Path(sys.argv[1]).resolve()
    target = (
        project_root
        / "supabase"
        / "functions"
        / "export-shipment-excel"
        / "index.ts"
    )
    if not target.is_file():
        raise SystemExit(f"target not found: {target}")

    with target.open("r", encoding="utf-8", newline="") as handle:
        source = handle.read()

    if "[EXCEL200C]" not in source or "zipSync(files, { level: 0 })" not in source:
        raise SystemExit(
            "Patch200C/C1 적용 상태가 아닙니다. 기존 패치 상태를 먼저 확인해 주세요."
        )

    old = r"/<f\b[^>]*>[\s\S]*?<\/f>/,"
    new = r"/<f\b[^>]*(?:\/>|>[\s\S]*?<\/f>)/,"

    old_count = source.count(old)
    new_count = source.count(new)
    if old_count == 0 and new_count == 1:
        print("Patch200C2 already applied")
        return 0
    if old_count != 1 or new_count != 0:
        raise SystemExit(
            f"unexpected source state: old={old_count}, new={new_count}"
        )

    patched = source.replace(old, new, 1)
    with target.open("w", encoding="utf-8", newline="") as handle:
        handle.write(patched)

    print("Patch200C2 applied: shared-formula followers now become standalone SUMIF formulas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
