from pathlib import Path

cwd = Path.cwd()

def rd(path):
    return path.read_text(encoding="utf-8-sig")

def wr(path, text):
    path.write_text(text, encoding="utf-8")

# ------------------------------------------------------------------
# 1) Statement adjustment layout: label | percent | amount
# ------------------------------------------------------------------
p = cwd / "lib/screens/statement_preview_dialog.dart"
s = rd(p)

start = s.find("    final isSpecialDiscount = discountGroupText.contains('특별');")
final_top = s.find("    final finalTop =", start)
if start < 0 or final_top < 0:
    raise SystemExit("statement adjustment block anchor not found")

statement_block = r'''    final isSpecialDiscount = discountGroupText.contains('특별');
    final regularDiscountUsd =
        isSpecialDiscount ? 0.0 : totalDiscountUsd;
    final specialDiscountUsd =
        isSpecialDiscount ? totalDiscountUsd : 0.0;

    // label | percent around 2/3 | amount at far right
    const adjustmentFont = 15.0;
    final labelRectW = totalW * .44;
    final percentX = totalX + totalW * .52;
    final percentW = totalW * .20;
    final amountX = totalX + totalW * .72;
    final amountW = totalW * .24;

    String discountAmountText(bool active, double amount) {
      if (!active || actualDiscountPctText.isEmpty) return '-';
      return '-${MoneyFormat.usd(amount)}';
    }

    _text(
      c,
      '할인',
      Rect.fromLTWH(totalX + 12, sumTop + 7, labelRectW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      !isSpecialDiscount && actualDiscountPctText.isNotEmpty
          ? actualDiscountPctText
          : '-',
      Rect.fromLTWH(percentX, sumTop + 7, percentW, adjH),
      adjustmentFont,
      bold: true,
      center: true,
    );
    _text(
      c,
      discountAmountText(!isSpecialDiscount, regularDiscountUsd),
      Rect.fromLTWH(amountX, sumTop + 7, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

    _text(
      c,
      '특별할인',
      Rect.fromLTWH(totalX + 12, sumTop + 34, labelRectW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      isSpecialDiscount && actualDiscountPctText.isNotEmpty
          ? actualDiscountPctText
          : '-',
      Rect.fromLTWH(percentX, sumTop + 34, percentW, adjH),
      adjustmentFont,
      bold: true,
      center: true,
    );
    _text(
      c,
      discountAmountText(isSpecialDiscount, specialDiscountUsd),
      Rect.fromLTWH(amountX, sumTop + 34, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

    _text(
      c,
      '세금 계산서(VAT)',
      Rect.fromLTWH(totalX + 12, sumTop + 61, labelRectW, adjH),
      adjustmentFont,
      bold: true,
    );
    _text(
      c,
      '-',
      Rect.fromLTWH(percentX, sumTop + 61, percentW, adjH),
      adjustmentFont,
      bold: true,
      center: true,
    );
    _text(
      c,
      '-',
      Rect.fromLTWH(amountX, sumTop + 61, amountW, adjH),
      adjustmentFont,
      bold: true,
      right: true,
    );

'''
s = s[:start] + statement_block + s[final_top:]
wr(p, s)

# ------------------------------------------------------------------
# 2) Quotation adjustment layout: same three visual columns
# ------------------------------------------------------------------
p = cwd / "lib/screens/quotation_preview_dialog.dart"
s = rd(p)
old_quote = """    _text(c, '할인', Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '세금 계산서(VAT)', Rect.fromLTWH(totalX + 12, sumTop + 61, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 61, totalW * .44, adjH), 16, bold: true, right: true);"""
new_quote = """    final adjustmentLabelW = totalW * .44;
    final adjustmentPercentX = totalX + totalW * .52;
    final adjustmentPercentW = totalW * .20;
    final adjustmentAmountX = totalX + totalW * .72;
    final adjustmentAmountW = totalW * .24;

    for (final row in <(String, double)>[
      ('할인', sumTop + 7),
      ('특별할인', sumTop + 34),
      ('세금 계산서(VAT)', sumTop + 61),
    ]) {
      _text(c, row.$1,
          Rect.fromLTWH(totalX + 12, row.$2, adjustmentLabelW, adjH),
          16, bold: true);
      _text(c, '-',
          Rect.fromLTWH(adjustmentPercentX, row.$2, adjustmentPercentW, adjH),
          16, bold: true, center: true);
      _text(c, '-',
          Rect.fromLTWH(adjustmentAmountX, row.$2, adjustmentAmountW, adjH),
          16, bold: true, right: true);
    }"""
if old_quote not in s:
    raise SystemExit("quotation adjustment block anchor not found")
s = s.replace(old_quote, new_quote, 1)
wr(p, s)

# ------------------------------------------------------------------
# 3) Excel exporter: customer-list values/title/signature
# ------------------------------------------------------------------
p = cwd / "supabase/functions/export-shipment-excel/index.ts"
s = rd(p)

fn_start = s.find("function seedCustomerListFromShipments(")
fn_end = s.find("\nfunction setCachedFormulaValue(", fn_start)
if fn_start < 0 or fn_end < 0:
    raise SystemExit("seedCustomerListFromShipments block not found")

new_seed = r'''function seedCustomerListFromShipments(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  routeKey: string,
  voyage: string,
): void {
  const path = workbookSheetPath(files, '고객 리스트');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);
  const prefix = routeReceiptPrefix(routeKey);
  const voyageNumber = String(voyage)
    .replace(/^V/i, '')
    .replace(/항차$/u, '')
    .trim();

  if (routeKey === 'kr_la_sea') {
    xml = setStringCellInSheet(
      xml,
      'A1',
      `Kor-Lao Sea ${voyageNumber}항차 고객 리스트 (ລາຍການລູກຄ້າຂອງທາງເຮືອ)`,
    );
  } else {
    const a1Match = xml.match(
      /<c\b[^>]*r="A1"[^>]*(?:\/>|>[\s\S]*?<\/c>)/,
    );
    if (a1Match) {
      const currentTitle = cellText(a1Match[0], strings);
      if (/xx/iu.test(currentTitle)) {
        xml = setStringCellInSheet(
          xml,
          'A1',
          currentTitle.replace(/xx/iu, voyageNumber),
        );
      }
    }
  }

  const byReceipt = new Map<string, Record<string, unknown>[]>();
  for (const shipment of shipments) {
    const receipt = String(shipment.receipt_number ?? '').trim();
    if (!receipt) continue;
    const key = receipt.toUpperCase();
    const list = byReceipt.get(key) ?? [];
    list.push(shipment);
    byReceipt.set(key, list);
  }

  for (const rowMatch of xml.matchAll(
    /<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g,
  )) {
    const rowNumber = Number(rowMatch[1]);
    if (rowNumber < 4 || rowNumber > 150) continue;

    const currentRow = rowMatch[0];
    const aRe = new RegExp(
      `<c\\b[^>]*r="A${rowNumber}"[^>]*(?:\\/>|>[\\s\\S]*?<\\/c>)`,
    );
    const aMatch = currentRow.match(aRe);
    if (!aMatch) continue;

    let receipt = cellText(aMatch[0], strings).trim();
    if (/\bxx\s*$/i.test(receipt) && prefix) {
      receipt = `${prefix} XX`;
      xml = setStringCellInSheet(xml, `A${rowNumber}`, receipt);
    }
    if (!receipt) continue;

    const rows = byReceipt.get(receipt.toUpperCase());
    if (!rows || rows.length === 0) continue;

    const first = rows[0];
    const name = String(first.consignee_name ?? '').trim();
    if (name) xml = setStringCellInSheet(xml, `B${rowNumber}`, name);

    const zones = rows
      .map((x) => String(x.unloading_zone ?? '').trim().toUpperCase())
      .filter(Boolean);
    const fixedZone = zones.includes('102')
      ? '102'
      : (zones.includes('F') ? 'F' : '');
    if (fixedZone) {
      // F/102 are final DB classifications: ignore the automatic C formula.
      xml = setStringCellInSheet(xml, `C${rowNumber}`, fixedZone);
    }

    const note = rows
      .map((x) => String(x.special_note_auto ?? '').trim())
      .filter(Boolean)
      .join(' / ');

    let signature = '';
    if (note.includes('지방배송(선결제)')) {
      signature = '지방배송(선결제)';
    } else if (note.includes('시내배송(선결제)')) {
      signature = '시내배송(선결제)';
    } else if (note.includes('지방배송')) {
      signature = '지방배송';
    } else if (note.includes('시내배송')) {
      signature = '시내배송';
    }
    if (signature) {
      xml = setStringCellInSheet(xml, `E${rowNumber}`, signature);
    }
  }

  files[path] = strToU8(xml);
}
'''
s = s[:fn_start] + new_seed + s[fn_end:]
s = s.replace(
    "seedCustomerListFromShipments(files, enrichedShipments);",
    "seedCustomerListFromShipments(files, enrichedShipments, routeKey, voyage);",
    1,
)

# ------------------------------------------------------------------
# 4) Excel customer-list signature colors using existing 4 delivery DXFs
# ------------------------------------------------------------------
cf_start = s.find("function applyDeliveryColorConditionalFormatting(")
cf_end = s.find("\nfunction normalizePhone(", cf_start)
if cf_start < 0 or cf_end < 0:
    raise SystemExit("applyDeliveryColorConditionalFormatting block not found")
cf = s[cf_start:cf_end]
closing = cf.rfind("\n}")
if closing < 0:
    raise SystemExit("conditional formatting closing brace not found")

customer_cf = r'''

  // 고객 리스트 서명란(E4:E150): 명세서와 같은 배송 색상.
  const customerListPath = workbookSheetPath(files, '고객 리스트');
  if (customerListPath && files[customerListPath]) {
    let customerXml = strFromU8(files[customerListPath]);
    if (!customerXml.includes('LK_CUSTOMER_DELIVERY_COLOR')) {
      const maxPriority = Math.max(
        0,
        ...[...customerXml.matchAll(/<cfRule\b[^>]*priority="(\d+)"/g)]
          .map((m) => Number(m[1] ?? 0)),
      );
      const customerRules = [
        { label: '지방배송', dxf: baseDxf + 0 },
        { label: '지방배송(선결제)', dxf: baseDxf + 1 },
        { label: '시내배송', dxf: baseDxf + 2 },
        { label: '시내배송(선결제)', dxf: baseDxf + 3 },
      ].map((r, i) =>
        `<cfRule type="expression" dxfId="${r.dxf}" priority="${maxPriority + i + 1}" stopIfTrue="1">` +
        `<formula>${escXml(`$E4="${r.label}"`)}</formula>` +
        `</cfRule>`
      ).join('');
      const customerBlock =
        `<!--LK_CUSTOMER_DELIVERY_COLOR-->` +
        `<conditionalFormatting sqref="E4:E150">${customerRules}</conditionalFormatting>`;

      if (customerXml.includes('<dataValidations ')) {
        customerXml = customerXml.replace(
          '<dataValidations ',
          `${customerBlock}<dataValidations `,
        );
      } else if (customerXml.includes('<pageMargins ')) {
        customerXml = customerXml.replace(
          '<pageMargins ',
          `${customerBlock}<pageMargins `,
        );
      } else {
        customerXml = customerXml.replace(
          '</worksheet>',
          `${customerBlock}</worksheet>`,
        );
      }
      files[customerListPath] = strToU8(customerXml);
    }
  }
'''
cf = cf[:closing] + customer_cf + cf[closing:]
s = s[:cf_start] + cf + s[cf_end:]
wr(p, s)

print("Patch183 applied.")
