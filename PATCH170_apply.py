from pathlib import Path

p=Path.cwd()/"lib"/"services"/"customer_benefit_service.dart"
if not p.exists():
    raise SystemExit("lib/services/customer_benefit_service.dart not found.")

text=p.read_text(encoding="utf-8-sig")

old="""  static bool _phoneMatches(String a, String b) {
    final aa = normalizePhone(a);
    final bb = normalizePhone(b);
    if (aa.isEmpty || bb.isEmpty) return false;
    if (aa == bb) return true;
    if (aa.length >= 8 && bb.length >= 8) {
      return aa.substring(aa.length - 8) == bb.substring(bb.length - 8);
    }
    return false;
  }

  static bool _nameMatches(
    String shipmentName,
    Iterable<String> candidates,
  ) {
    final target = _normalizeName(shipmentName);
    if (target.isEmpty) return false;
    return candidates.any(
      (value) =>
          value.trim().isNotEmpty && _normalizeName(value) == target,
    );
  }
"""

new="""  static bool _phoneMatches(String a, String b) {
    final aa = normalizePhone(a);
    final bb = normalizePhone(b);
    if (aa.isEmpty || bb.isEmpty) return false;
    if (aa == bb) return true;
    if (aa.length >= 8 && bb.length >= 8) {
      if (aa.substring(aa.length - 8) == bb.substring(bb.length - 8)) {
        return true;
      }
      // BASE 배송표 한 셀에 전화번호가 2개 이상 들어간 경우도 허용.
      if (aa.contains(bb) || bb.contains(aa)) return true;
    }
    return false;
  }

  static Iterable<String> _nameTokens(String value) sync* {
    final normalized = _normalizeName(value);
    if (normalized.isEmpty) return;
    yield normalized;

    // 실무 BASE 표기: 이경화/이경희, 이름,이름, 이름(보조명) 등.
    for (final part in normalized.split(RegExp(r'[/,;|()\\\\]+'))) {
      final token = _normalizeName(part);
      if (token.isNotEmpty) yield token;
    }
  }

  static bool _nameMatches(
    String shipmentName,
    Iterable<String> candidates,
  ) {
    final shipmentTokens = _nameTokens(shipmentName).toSet();
    if (shipmentTokens.isEmpty) return false;

    for (final value in candidates) {
      if (value.trim().isEmpty) continue;
      final candidateTokens = _nameTokens(value).toSet();
      if (shipmentTokens.any(candidateTokens.contains)) return true;
    }
    return false;
  }
"""

if text.count(old)!=1:
    raise SystemExit(f"name/phone matcher anchor expected 1, found {text.count(old)}. No file changed.")
text=text.replace(old,new,1)

# source_no 10000+ is only an internal collision-safe id; don't print it as customer-facing No.
old2="""    final no = sourceNo == null ? '' : '(${sourceNo!}) ';"""
new2="""    final displayNo = sourceNo == null
        ? null
        : (sourceNo! >= 10000 ? sourceNo! - 10000 : sourceNo!);
    final no = displayNo == null ? '' : '($displayNo) ';"""
if text.count(old2)!=1:
    raise SystemExit(f"statement source no anchor expected 1, found {text.count(old2)}. No file changed.")
text=text.replace(old2,new2,1)

p.write_text(text,encoding="utf-8")
print("Patch170 applied.")
