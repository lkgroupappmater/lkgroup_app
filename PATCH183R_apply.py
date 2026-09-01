from pathlib import Path
import re, shutil
cwd=Path.cwd()
def rd(p): return p.read_text(encoding='utf-8-sig')
def wr(p,s): p.write_text(s,encoding='utf-8')
shutil.copy2(cwd/'customer_list_management_screen.txt', cwd/'lib/screens/customer_list_management_screen.dart')

# Statement layout
p=cwd/'lib/screens/statement_preview_dialog.dart'
s=rd(p)
s=s.replace("""    _text(
      c,
      '할인',
      Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .42, adjH),
      15,
      bold: true,
    );
    _text(
      c,
      discountValueText(
        active: !isSpecialDiscount && actualDiscountPctText.isNotEmpty,
        amountUsd: regularDiscountUsd,
      ),
      Rect.fromLTWH(totalX + totalW * .42, sumTop + 7, totalW * .54, adjH),
      15,
      bold: true,
      right: true,
    );""","""    _text(
      c,
      '할인',
      Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .44, adjH),
      15,
      bold: true,
    );
    _text(
      c,
      !isSpecialDiscount && actualDiscountPctText.isNotEmpty
          ? actualDiscountPctText
          : '-',
      Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .20, adjH),
      15,
      bold: true,
      center: true,
    );
    _text(
      c,
      !isSpecialDiscount && actualDiscountPctText.isNotEmpty
          ? '-${MoneyFormat.usd(regularDiscountUsd)}'
          : '-',
      Rect.fromLTWH(totalX + totalW * .72, sumTop + 7, totalW * .24, adjH),
      15,
      bold: true,
      right: true,
    );""",1)
s=s.replace("""    _text(
      c,
      '특별할인',
      Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .42, adjH),
      15,
      bold: true,
    );""","""    _text(
      c,
      '특별할인',
      Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .44, adjH),
      15,
      bold: true,
    );
    _text(
      c,
      isSpecialDiscount && actualDiscountPctText.isNotEmpty
          ? actualDiscountPctText
          : '-',
      Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .20, adjH),
      15,
      bold: true,
      center: true,
    );""",1)
s=s.replace('Rect.fromLTWH(totalX + totalW * .42, sumTop + 34, totalW * .54, adjH),','Rect.fromLTWH(totalX + totalW * .72, sumTop + 34, totalW * .24, adjH),',1)
wr(p,s)

# Quotation layout
p=cwd/'lib/screens/quotation_preview_dialog.dart'
s=rd(p)
old="""    _text(c, '할인', Rect.fromLTWH(totalX + 12, sumTop + 7, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 7, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '특별할인', Rect.fromLTWH(totalX + 12, sumTop + 34, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 34, totalW * .44, adjH), 16, bold: true, right: true);
    _text(c, '세금 계산서(VAT)', Rect.fromLTWH(totalX + 12, sumTop + 61, totalW * .46, adjH), 16, bold: true);
    _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, sumTop + 61, totalW * .44, adjH), 16, bold: true, right: true);"""
new="""    for (final row in <(String, double)>[
      ('할인', sumTop + 7),
      ('특별할인', sumTop + 34),
      ('세금 계산서(VAT)', sumTop + 61),
    ]) {
      _text(c, row.$1, Rect.fromLTWH(totalX + 12, row.$2, totalW * .44, adjH), 16, bold: true);
      _text(c, '-', Rect.fromLTWH(totalX + totalW * .52, row.$2, totalW * .20, adjH), 16, bold: true, center: true);
      _text(c, '-', Rect.fromLTWH(totalX + totalW * .72, row.$2, totalW * .24, adjH), 16, bold: true, right: true);
    }"""
if old in s: s=s.replace(old,new,1)
wr(p,s)

# Excel customer list
p=cwd/'supabase/functions/export-shipment-excel/index.ts'
s=rd(p)
start=s.find('function seedCustomerListFromShipments(')
end=s.find('\nfunction setCachedFormulaValue(',start)
if start<0 or end<0: raise SystemExit('Excel customer list function not found')
new_seed='function seedCustomerListFromShipments(\n  files: Record<string, Uint8Array>,\n  shipments: Record<string, unknown>[],\n  routeKey: string,\n  voyage: string,\n): void {\n  const path = workbookSheetPath(files, \'고객 리스트\');\n  if (!path || !files[path]) return;\n  let xml = strFromU8(files[path]);\n  const strings = sharedStrings(files);\n  const prefix = routeReceiptPrefix(routeKey);\n  const voyageNumber = String(voyage)\n    .replace(/^V/i, \'\')\n    .replace(/항차$/u, \'\')\n    .trim();\n\n  if (routeKey === \'kr_la_sea\') {\n    xml = setStringCellInSheet(\n      xml,\n      \'A1\',\n      `Kor-Lao Sea ${voyageNumber}항차 고객 리스트 (ລາຍການລູກຄ້າຂອງທາງເຮືອ)`,\n    );\n  }\n\n  const groups = new Map<string, Record<string, unknown>[]>();\n  for (const shipment of shipments) {\n    const receipt = String(shipment.receipt_number ?? \'\').trim();\n    if (!receipt) continue;\n    const key = receipt.toUpperCase();\n    const list = groups.get(key) ?? [];\n    list.push(shipment);\n    groups.set(key, list);\n  }\n\n  const compactName = (value: unknown) =>\n    String(value ?? \'\')\n      .replace(/[\\s/,_()\\-]+/g, \'\')\n      .toLowerCase();\n\n  const fixed102Names = [\n    \'박성호\',\'정석진\',\'이동현\',\'정민주\',\'박상욱\',\n    \'박상용\',\'임홍식\',\'진정우\',\'최현석\',\n  ];\n\n  for (const rowMatch of xml.matchAll(\n    /<row\\b[^>]*r="(\\d+)"[^>]*>[\\s\\S]*?<\\/row>/g,\n  )) {\n    const rowNumber = Number(rowMatch[1]);\n    if (rowNumber < 4 || rowNumber > 150) continue;\n    const rowXml = rowMatch[0];\n    const aRe = new RegExp(\n      `<c\\\\b[^>]*r="A${rowNumber}"[^>]*(?:\\\\/>|>[\\\\s\\\\S]*?<\\\\/c>)`,\n    );\n    const aMatch = rowXml.match(aRe);\n    if (!aMatch) continue;\n\n    let receipt = cellText(aMatch[0], strings).trim();\n    if (/\\bxx\\s*$/i.test(receipt) && prefix) {\n      receipt = `${prefix} XX`;\n      xml = setStringCellInSheet(xml, `A${rowNumber}`, receipt);\n    }\n    if (!receipt) continue;\n\n    const rows = groups.get(receipt.toUpperCase());\n    if (!rows?.length) continue;\n\n    const first = rows[0];\n    const name = String(first.consignee_name ?? \'\').trim();\n    if (name) xml = setStringCellInSheet(xml, `B${rowNumber}`, name);\n\n    const note = rows\n      .map((x) => String(x.special_note_auto ?? \'\').trim())\n      .filter(Boolean)\n      .join(\' / \');\n    const normalizedName = compactName(name);\n\n    const isDeliveryF =\n      note.includes(\'지방배송\') || note.includes(\'시내배송\');\n    const isNamedF =\n      normalizedName.startsWith(\'김요셉\') ||\n      normalizedName.startsWith(\'뷰티판다\');\n    const isFixed102 = fixed102Names.some(\n      (fixed) => normalizedName.startsWith(compactName(fixed)),\n    );\n\n    // Normal customers KEEP the original Excel A/B/C/F formula.\n    // Only explicit business-rule exceptions override Area Categorized.\n    if (isFixed102) {\n      xml = setStringCellInSheet(xml, `C${rowNumber}`, \'102\');\n    } else if (isDeliveryF || isNamedF) {\n      xml = setStringCellInSheet(xml, `C${rowNumber}`, \'F\');\n    }\n\n    let signature = \'\';\n    if (note.includes(\'지방배송(선결제)\')) {\n      signature = \'지방배송(선결제)\';\n    } else if (note.includes(\'시내배송(선결제)\')) {\n      signature = \'시내배송(선결제)\';\n    } else if (note.includes(\'지방배송\')) {\n      signature = \'지방배송\';\n    } else if (note.includes(\'시내배송\')) {\n      signature = \'시내배송\';\n    }\n    if (signature) {\n      xml = setStringCellInSheet(xml, `E${rowNumber}`, signature);\n    }\n  }\n\n  files[path] = strToU8(xml);\n}\n'
s=s[:start]+new_seed+s[end:]
s=s.replace('seedCustomerListFromShipments(files, enrichedShipments);','seedCustomerListFromShipments(files, enrichedShipments, routeKey, voyage);',1)
cf_start=s.find('function applyDeliveryColorConditionalFormatting(')
cf_end=s.find('\nfunction normalizePhone(',cf_start)
if cf_start<0 or cf_end<0: raise SystemExit('Excel delivery color function not found')
cf=s[cf_start:cf_end]
extra_cf='\n  const customerPath = workbookSheetPath(files, \'고객 리스트\');\n  if (customerPath && files[customerPath]) {\n    let customerXml = strFromU8(files[customerPath]);\n    if (!customerXml.includes(\'LK_CUSTOMER_LIST_DELIVERY_COLOR\')) {\n      const maxPriority = Math.max(\n        0,\n        ...[...customerXml.matchAll(/<cfRule\\\\b[^>]*priority="(\\\\d+)"/g)]\n          .map((m) => Number(m[1] ?? 0)),\n      );\n      const rules = [\n        { label: \'시내배송(선결제)\', dxf: baseDxf + 3 },\n        { label: \'시내배송\', dxf: baseDxf + 2 },\n        { label: \'지방배송(선결제)\', dxf: baseDxf + 1 },\n        { label: \'지방배송\', dxf: baseDxf + 0 },\n      ].map((r, i) =>\n        `<cfRule type="expression" dxfId="${r.dxf}" priority="${maxPriority + i + 1}" stopIfTrue="1">` +\n        `<formula>${escXml(`$E4="${r.label}"`)}</formula></cfRule>`\n      ).join(\'\');\n      const block =\n        `<!--LK_CUSTOMER_LIST_DELIVERY_COLOR-->` +\n        `<conditionalFormatting sqref="E4:E150">${rules}</conditionalFormatting>`;\n      if (customerXml.includes(\'<dataValidations \')) {\n        customerXml = customerXml.replace(\n          \'<dataValidations \',\n          `${block}<dataValidations `,\n        );\n      } else if (customerXml.includes(\'<pageMargins \')) {\n        customerXml = customerXml.replace(\n          \'<pageMargins \',\n          `${block}<pageMargins `,\n        );\n      } else {\n        customerXml = customerXml.replace(\n          \'</worksheet>\',\n          `${block}</worksheet>`,\n        );\n      }\n      files[customerPath] = strToU8(customerXml);\n    }\n  }\n'
if 'LK_CUSTOMER_LIST_DELIVERY_COLOR' not in cf:
    close=cf.rfind('\n}')
    if close<0: raise SystemExit('Excel delivery color function close not found')
    cf=cf[:close]+extra_cf+cf[close:]
    s=s[:cf_start]+cf+s[cf_end:]
wr(p,s)

# Management menu: clone existing unloading menu item so local design is preserved
menu_file=None
for candidate in (cwd/'lib').rglob('*.dart'):
    if candidate.name=='customer_list_management_screen.dart': continue
    text=rd(candidate)
    if 'UnloadingListManagementScreen' in text:
        menu_file=candidate; break
if menu_file is None: raise SystemExit('UnloadingListManagementScreen menu file not found')
s=rd(menu_file)
if 'customer_list_management_screen.dart' not in s:
    imports=list(re.finditer(r"^import\s+['\"].*?['\"];\s*$",s,re.M))
    if not imports: raise SystemExit('menu import anchor not found')
    pos=imports[-1].end()
    target=(cwd/'lib/screens/customer_list_management_screen.dart').relative_to(menu_file.parent)
    imp=str(target).replace('\\\\','/')
    if not imp.startswith('.'): imp='./'+imp
    s=s[:pos]+f"\nimport '{imp}';"+s[pos:]
if 'CustomerListManagementScreen' not in s:
    dp=s.find('UnloadingListManagementScreen')
    starts=[s.rfind('ListTile(',0,dp),s.rfind('Card(',0,dp),s.rfind('InkWell(',0,dp)]
    st=max(starts)
    if st<0: raise SystemExit('unloading menu block start not found')
    par=s.find('(',st); depth=0; en=-1
    for i in range(par,len(s)):
        if s[i]=='(': depth+=1
        elif s[i]==')':
            depth-=1
            if depth==0:
                j=i+1
                while j<len(s) and s[j] in ' \t\r\n': j+=1
                en=j+1 if j<len(s) and s[j] in ',;' else i+1
                break
    if en<0: raise SystemExit('unloading menu block end not found')
    block=s[st:en]
    customer=block.replace('UnloadingListManagementScreen','CustomerListManagementScreen').replace('하역 자료 관리','고객 리스트').replace('하역 자료','고객 리스트').replace('Icons.inventory_2_outlined','Icons.people_alt_outlined').replace('Icons.view_module_outlined','Icons.people_alt_outlined')
    s=s[:en]+'\n'+customer+s[en:]
wr(menu_file,s)
(cwd/'customer_list_management_screen.txt').unlink(missing_ok=True)
print(f'Patch183R applied; menu file={menu_file}')