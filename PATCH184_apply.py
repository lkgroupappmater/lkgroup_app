from pathlib import Path
import re, shutil
cwd=Path.cwd()
def rd(p): return p.read_text(encoding='utf-8-sig')
def wr(p,s): p.write_text(s,encoding='utf-8')

# 0. New customer-list screen
shutil.copy2(cwd/'customer_list_management_screen.txt', cwd/'lib/screens/customer_list_management_screen.dart')

# 1. FreightService: non-numeric strong phone tokens (e.g. CEO) are allowed
#    and discount percent still comes ONLY from DB/chart.
p=cwd/'lib/services/freight_service.dart'
s=rd(p)
old="""    final normalizedPhone = _digits(phone);\n    if (!SupabaseConfig.isConfigured ||\n        name.trim().isEmpty ||\n        normalizedPhone.isEmpty) {\n      return null;\n    }"""
new="""    final normalizedPhone = _digits(phone);\n    if (!SupabaseConfig.isConfigured || name.trim().isEmpty) {\n      return null;\n    }"""
if old in s: s=s.replace(old,new,1)
old2="""  static bool _phoneMatches(String a, String b) {\n    final aa = _digits(a);\n    final bb = _digits(b);\n    if (aa.isEmpty || bb.isEmpty) return false;\n    if (aa == bb) return true;\n    if (aa.length >= 8 && bb.length >= 8) {\n      return aa.substring(aa.length - 8) ==\n          bb.substring(bb.length - 8);\n    }\n    return false;\n  }"""
new2="""  static bool _phoneMatches(String a, String b) {\n    final aa = _digits(a);\n    final bb = _digits(b);\n    if (aa.isNotEmpty && bb.isNotEmpty) {\n      if (aa == bb) return true;\n      if (aa.length >= 8 && bb.length >= 8) {\n        return aa.substring(aa.length - 8) ==\n            bb.substring(bb.length - 8);\n      }\n      return false;\n    }\n\n    // Some confirmed BASE identities use a non-numeric token such as CEO.\n    // This is still a strong phone/identity match: exact token on both sides.\n    final rawA = a.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), '');\n    final rawB = b.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), '');\n    return rawA.isNotEmpty && rawA == rawB;\n  }"""
if old2 not in s: raise SystemExit('FreightService phone matcher anchor missing')
s=s.replace(old2,new2,1)
wr(p,s)

# 2. Statement: replace entire adjustment block structurally.
p=cwd/'lib/screens/statement_preview_dialog.dart'
s=rd(p)
st=s.find("    final isSpecialDiscount = discountGroupText.contains('특별');")
en=s.find('    final finalTop =',st)
if st<0 or en<0: raise SystemExit('Statement adjustment block not found')
block="    final isSpecialDiscount = discountGroupText.contains('특별');\n    final regularDiscountUsd =\n        isSpecialDiscount ? 0.0 : totalDiscountUsd;\n    final specialDiscountUsd =\n        isSpecialDiscount ? totalDiscountUsd : 0.0;\n\n    // Three clear columns: label | percent (~2/3) | amount (far right).\n    const adjustmentFont = 15.0;\n    final labelW = totalW * .46;\n    final percentX = totalX + totalW * .54;\n    final percentW = totalW * .18;\n    final amountX = totalX + totalW * .74;\n    final amountW = totalW * .22;\n\n    _text(\n      c,\n      '할인',\n      Rect.fromLTWH(totalX + 12, sumTop + 7, labelW, adjH),\n      adjustmentFont,\n      bold: true,\n    );\n    _text(\n      c,\n      !isSpecialDiscount && actualDiscountPctText.isNotEmpty\n          ? actualDiscountPctText\n          : '-',\n      Rect.fromLTWH(percentX, sumTop + 7, percentW, adjH),\n      adjustmentFont,\n      bold: true,\n      center: true,\n    );\n    _text(\n      c,\n      !isSpecialDiscount && actualDiscountPctText.isNotEmpty\n          ? '-${MoneyFormat.usd(regularDiscountUsd)}'\n          : '-',\n      Rect.fromLTWH(amountX, sumTop + 7, amountW, adjH),\n      adjustmentFont,\n      bold: true,\n      right: true,\n    );\n\n    _text(\n      c,\n      '특별할인',\n      Rect.fromLTWH(totalX + 12, sumTop + 34, labelW, adjH),\n      adjustmentFont,\n      bold: true,\n    );\n    _text(\n      c,\n      isSpecialDiscount && actualDiscountPctText.isNotEmpty\n          ? actualDiscountPctText\n          : '-',\n      Rect.fromLTWH(percentX, sumTop + 34, percentW, adjH),\n      adjustmentFont,\n      bold: true,\n      center: true,\n    );\n    _text(\n      c,\n      isSpecialDiscount && actualDiscountPctText.isNotEmpty\n          ? '-${MoneyFormat.usd(specialDiscountUsd)}'\n          : '-',\n      Rect.fromLTWH(amountX, sumTop + 34, amountW, adjH),\n      adjustmentFont,\n      bold: true,\n      right: true,\n    );\n\n    _text(\n      c,\n      '세금 계산서(VAT)',\n      Rect.fromLTWH(totalX + 12, sumTop + 61, labelW, adjH),\n      adjustmentFont,\n      bold: true,\n    );\n    _text(\n      c,\n      '-',\n      Rect.fromLTWH(percentX, sumTop + 61, percentW, adjH),\n      adjustmentFont,\n      bold: true,\n      center: true,\n    );\n    _text(\n      c,\n      '-',\n      Rect.fromLTWH(amountX, sumTop + 61, amountW, adjH),\n      adjustmentFont,\n      bold: true,\n      right: true,\n    );\n\n"
s=s[:st]+block+s[en:]
wr(p,s)

# 3. Quotation: same 3-column visual layout.
p=cwd/'lib/screens/quotation_preview_dialog.dart'
s=rd(p)
qst=s.find("    _text(c, '할인',")
qen=s.find('    final finalTop =',qst)
if qst>=0 and qen>qst:
    qblock="""    for (final row in <(String, double)>[\n      ('할인', sumTop + 7),\n      ('특별할인', sumTop + 34),\n      ('세금 계산서(VAT)', sumTop + 61),\n    ]) {\n      _text(c, row.$1, Rect.fromLTWH(totalX + 12, row.$2, totalW * .46, adjH), 16, bold: true);\n      _text(c, '-', Rect.fromLTWH(totalX + totalW * .54, row.$2, totalW * .18, adjH), 16, bold: true, center: true);\n      _text(c, '-', Rect.fromLTWH(totalX + totalW * .74, row.$2, totalW * .22, adjH), 16, bold: true, right: true);\n    }\n\n"""
    s=s[:qst]+qblock+s[qen:]
wr(p,s)

# 4. Excel customer-list output corrected.
p=cwd/'supabase/functions/export-shipment-excel/index.ts'
s=rd(p)
st=s.find('function seedCustomerListFromShipments(')
en=s.find('\nfunction setCachedFormulaValue(',st)
if st<0 or en<0: raise SystemExit('Excel customer-list function missing')
seed='function seedCustomerListFromShipments(\n  files: Record<string, Uint8Array>,\n  shipments: Record<string, unknown>[],\n  routeKey: string,\n  voyage: string,\n): void {\n  const path = workbookSheetPath(files, \'고객 리스트\');\n  if (!path || !files[path]) return;\n  let xml = strFromU8(files[path]);\n  const strings = sharedStrings(files);\n  const prefix = routeReceiptPrefix(routeKey);\n  const voyageNumber = String(voyage)\n    .replace(/^V/i, \'\')\n    .replace(/항차$/u, \'\')\n    .trim();\n\n  if (routeKey === \'kr_la_sea\') {\n    xml = setStringCellInSheet(\n      xml,\n      \'A1\',\n      `Kor-Lao Sea ${voyageNumber}항차 고객 리스트 (ລາຍການລູກຄ້າຂອງທາງເຮືອ)`,\n    );\n  }\n\n  const groups = new Map<string, Record<string, unknown>[]>();\n  for (const shipment of shipments) {\n    const receipt = String(shipment.receipt_number ?? \'\').trim();\n    if (!receipt) continue;\n    const key = receipt.toUpperCase();\n    const list = groups.get(key) ?? [];\n    list.push(shipment);\n    groups.set(key, list);\n  }\n\n  const compactName = (value: unknown) =>\n    String(value ?? \'\').replace(/[\\s/,_()\\-]+/g, \'\').toLowerCase();\n\n  const fixed102Names = [\n    \'박성호\',\'정석진\',\'이동현\',\'정민주\',\'박상욱\',\n    \'박상용\',\'임홍식\',\'진정우\',\'최현석\',\n  ];\n\n  for (const rowMatch of xml.matchAll(\n    /<row\\b[^>]*r="(\\d+)"[^>]*>[\\s\\S]*?<\\/row>/g,\n  )) {\n    const rowNumber = Number(rowMatch[1]);\n    if (rowNumber < 4 || rowNumber > 150) continue;\n    const rowXml = rowMatch[0];\n    const aRe = new RegExp(\n      `<c\\\\b[^>]*r="A${rowNumber}"[^>]*(?:\\\\/>|>[\\\\s\\\\S]*?<\\\\/c>)`,\n    );\n    const aMatch = rowXml.match(aRe);\n    if (!aMatch) continue;\n\n    let receipt = cellText(aMatch[0], strings).trim();\n    if (/\\bxx\\s*$/i.test(receipt) && prefix) {\n      receipt = `${prefix} XX`;\n      xml = setStringCellInSheet(xml, `A${rowNumber}`, receipt);\n    }\n    if (!receipt) continue;\n\n    const rows = groups.get(receipt.toUpperCase());\n    if (!rows?.length) continue;\n\n    const first = rows[0];\n    const name = String(first.consignee_name ?? \'\').trim();\n    if (name) xml = setStringCellInSheet(xml, `B${rowNumber}`, name);\n\n    const note = rows\n      .map((x) => String(x.special_note_auto ?? \'\').trim())\n      .filter(Boolean)\n      .join(\' / \');\n    const normalizedName = compactName(name);\n\n    const isDeliveryF =\n      note.includes(\'지방배송\') || note.includes(\'시내배송\');\n    const isNamedF =\n      normalizedName.startsWith(\'김요셉\') ||\n      normalizedName.startsWith(\'뷰티판다\');\n    const isFixed102 = fixed102Names.some(\n      (fixed) => normalizedName.startsWith(compactName(fixed)),\n    );\n\n    // Keep the original A/B/C/F Excel formula for ordinary customers.\n    // Override ONLY explicit business exceptions.\n    if (isFixed102) {\n      xml = setStringCellInSheet(xml, `C${rowNumber}`, \'102\');\n    } else if (isDeliveryF || isNamedF) {\n      xml = setStringCellInSheet(xml, `C${rowNumber}`, \'F\');\n    }\n\n    let signature = \'\';\n    if (note.includes(\'지방배송(선결제)\')) {\n      signature = \'지방배송(선결제)\';\n    } else if (note.includes(\'시내배송(선결제)\')) {\n      signature = \'시내배송(선결제)\';\n    } else if (note.includes(\'지방배송\')) {\n      signature = \'지방배송\';\n    } else if (note.includes(\'시내배송\')) {\n      signature = \'시내배송\';\n    }\n    if (signature) {\n      xml = setStringCellInSheet(xml, `E${rowNumber}`, signature);\n    }\n  }\n\n  files[path] = strToU8(xml);\n}\n'
s=s[:st]+seed+s[en:]
s=s.replace('seedCustomerListFromShipments(files, enrichedShipments);','seedCustomerListFromShipments(files, enrichedShipments, routeKey, voyage);',1)
wr(p,s)

# 5. Management menu: patch ONLY the actual file containing visible title + destination.
menu=None
for f in (cwd/'lib').rglob('*.dart'):
    if f.name=='customer_list_management_screen.dart': continue
    t=rd(f)
    if '하역 자료 관리' in t and 'UnloadingListManagementScreen' in t:
        menu=f; break
if menu is None:
    raise SystemExit('Actual management menu block with 하역 자료 관리 not found')
s=rd(menu)
if 'customer_list_management_screen.dart' not in s:
    imports=list(re.finditer(r"^import\s+['\"].*?['\"];\s*$",s,re.M))
    if not imports: raise SystemExit('Management menu import anchor missing')
    pos=imports[-1].end()
    rel=(cwd/'lib/screens/customer_list_management_screen.dart').relative_to(menu.parent)
    imp=str(rel).replace('\\\\','/')
    if not imp.startswith('.'): imp='./'+imp
    s=s[:pos]+f"\nimport '{imp}';"+s[pos:]
if 'CustomerListManagementScreen' not in s:
    dp=s.find('UnloadingListManagementScreen')
    # Find the nearest statement/widget that also contains the visible menu title.
    title=s.rfind('하역 자료 관리',0,dp+1)
    if title<0: title=s.find('하역 자료 관리',dp)
    candidates=[s.rfind('ListTile(',0,dp),s.rfind('Card(',0,dp),s.rfind('InkWell(',0,dp),s.rfind('_build',0,dp)]
    st=max(candidates)
    if st<0: raise SystemExit('Management menu widget start missing')
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
    if en<0: raise SystemExit('Management menu widget end missing')
    block=s[st:en]
    if '하역 자료 관리' not in block or 'UnloadingListManagementScreen' not in block:
        raise SystemExit('Located block is not the actual unloading menu item')
    customer=block.replace('UnloadingListManagementScreen','CustomerListManagementScreen').replace('하역 자료 관리','고객 리스트').replace('하역 자료','고객 리스트').replace('Icons.inventory_2_outlined','Icons.people_alt_outlined').replace('Icons.view_module_outlined','Icons.people_alt_outlined')
    s=s[:en]+'\n'+customer+s[en:]
wr(menu,s)

# 6. Verify the patch really landed. Fail loudly if not.
checks=[]
checks.append(('customer screen', (cwd/'lib/screens/customer_list_management_screen.dart').exists()))
checks.append(('menu link', 'CustomerListManagementScreen' in rd(menu) and '고객 리스트' in rd(menu)))
checks.append(('statement percent position', 'final percentX = totalX + totalW * .54;' in rd(cwd/'lib/screens/statement_preview_dialog.dart')))
checks.append(('CEO identity matcher', 'Some confirmed BASE identities use a non-numeric token' in rd(cwd/'lib/services/freight_service.dart')))
checks.append(('Excel corrected zone comment', 'Only explicit business exceptions override Area Categorized' in rd(cwd/'supabase/functions/export-shipment-excel/index.ts')))
bad=[name for name,ok in checks if not ok]
if bad: raise SystemExit('PATCH VERIFY FAILED: '+', '.join(bad))
(cwd/'customer_list_management_screen.txt').unlink(missing_ok=True)
print('PATCH184 VERIFIED OK')
print('Management menu file:', menu)
for name,ok in checks: print('[OK]' if ok else '[FAIL]', name)