from pathlib import Path

p = Path.cwd() / "supabase" / "functions" / "export-shipment-excel" / "index.ts"
if not p.exists():
    raise SystemExit("supabase/functions/export-shipment-excel/index.ts not found")

s = p.read_text(encoding="utf-8-sig")

old1 = """  if (existing) return sheetXml.replace(rowXml, rowXml.replace(cellRe, replacement));
  return sheetXml.replace(rowXml, updateCell(rowXml, rowNumber, column, '', 'text').replace(new RegExp(`<c\\\\b[^>]*r="${ref}"[^>]*(?:\\\\/>|>[\\\\s\\\\S]*?<\\\\/c>)`), replacement));
}"""

new1 = """  // IMPORTANT: replacement contains Excel formulas such as $N$2.
  // JavaScript String.replace(re, "text with $2") treats $2 as regex capture group,
  // which corrupted exported formulas (e.g. $N s="246") and made Excel repair the file.
  // Always use a callback so '$' is written literally.
  if (existing) {
    const updatedRow = rowXml.replace(cellRe, () => replacement);
    return sheetXml.replace(rowXml, updatedRow);
  }

  const seeded = updateCell(rowXml, rowNumber, column, '', 'text');
  const targetRe = new RegExp(
    `<c\\\\b[^>]*r="${ref}"[^>]*(?:\\\\/>|>[\\\\s\\\\S]*?<\\\\/c>)`,
  );
  const updatedRow = seeded.replace(targetRe, () => replacement);
  return sheetXml.replace(rowXml, updatedRow);
}"""

if s.count(old1) != 1:
    raise SystemExit(f"setFormulaCellInSheet anchor expected 1, found {s.count(old1)}")
s = s.replace(old1, new1, 1)

old2 = """  xml = setFormulaCellInSheet(xml, 'N3', remarkFormula);
  xml = setFormulaCellInSheet(xml, 'N4', inlandFormula);
  xml = setFormulaCellInSheet(xml, 'N5', deliveryTypeFormula);
  files[path] = strToU8(xml);"""

new2 = """  // N2:N3 and L4:N4 are merged areas in the real SEA template.
  // Writing helper formulas into N3/N4 caused Excel to repair/remove records.
  // The visible Remark/Inland target formulas above are sufficient.
  // N5 helper is also intentionally omitted to keep the original template untouched.
  void deliveryTypeFormula;
  files[path] = strToU8(xml);"""

if s.count(old2) != 1:
    raise SystemExit(f"N3-N5 helper anchor expected 1, found {s.count(old2)}")
s = s.replace(old2, new2, 1)

p.write_text(s, encoding="utf-8")
print("Patch173 applied.")
