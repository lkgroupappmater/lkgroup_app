from pathlib import Path
R=Path.cwd()

p=R/'lib/services/freight_service.dart'; s=p.read_text(encoding='utf-8-sig')
s=s.replace("if (!_phoneMatches(normalizedPhone, '${row['phone'] ?? ''}')) {", "if (!_phoneMatches(phone, '${row['phone'] ?? ''}')) {",1)
if s.count('normalizedPhone')==1: s=s.replace('    final normalizedPhone = _digits(phone);\n','',1)
p.write_text(s,encoding='utf-8')

def right_final(path, replacements):
    p=R/path; s=p.read_text(encoding='utf-8-sig')
    for a,b in replacements: s=s.replace(a,b)
    st=s.find('    final finalTop = sumTop + 92;'); en=s.find('    final payTop =',st)
    if st<0 or en<0: raise SystemExit(path+' final total anchors missing')
    blk=s[st:en].replace('20, bold: true, center: true);','20, bold: true, right: true);')
    p.write_text(s[:st]+blk+s[en:],encoding='utf-8')

right_final('lib/screens/statement_preview_dialog.dart',[
("'USD    ' + MoneyFormat.usd(finalUsd)","'USD     ${MoneyFormat.usd(finalUsd)}'"),
("'KIP    ' + MoneyFormat.kip(finalUsd * freight.rates.appliedKip)","'KIP     ${MoneyFormat.kip(finalUsd * freight.rates.appliedKip)}'"),
("'THB    ' + MoneyFormat.thb(finalUsd * freight.rates.appliedThb)","'THB     ${MoneyFormat.thb(finalUsd * freight.rates.appliedThb)}'"),
("'KRW    ' + MoneyFormat.krw(finalUsd * freight.rates.appliedKrw)","'KRW     ${MoneyFormat.krw(finalUsd * freight.rates.appliedKrw)}'"),
])

p=R/'lib/screens/quotation_preview_dialog.dart'; s=p.read_text(encoding='utf-8-sig')
s=s.replace('totalW * .44, adjH','totalW * .48, adjH')
s=s.replace('totalX + totalW * .52, row.$2, totalW * .20','totalX + totalW * .58, row.$2, totalW * .18')
s=s.replace('totalX + totalW * .72, row.$2, totalW * .24','totalX + totalW * .78, row.$2, totalW * .18')
p.write_text(s,encoding='utf-8')
right_final('lib/screens/quotation_preview_dialog.dart',[
("'USD    ' + MoneyFormat.usd(usd)","'USD     ${MoneyFormat.usd(usd)}'"),
("'KIP    ' + MoneyFormat.kip(usd * rates.appliedKip)","'KIP     ${MoneyFormat.kip(usd * rates.appliedKip)}'"),
("'THB    ' + MoneyFormat.thb(usd * rates.appliedThb)","'THB     ${MoneyFormat.thb(usd * rates.appliedThb)}'"),
("'KRW    ' + MoneyFormat.krw(usd * rates.appliedKrw)","'KRW     ${MoneyFormat.krw(usd * rates.appliedKrw)}'"),
])

p=R/'lib/screens/customer_list_management_screen.dart'
s=p.read_text(encoding='utf-8-sig')
# Fix mobile selector overflow: Expanded parent already exists; isExpanded and smaller padding.
s=s.replace('value: items.contains(value) ? value : null,\n        decoration:', 'value: items.contains(value) ? value : null,\n        isExpanded: true,\n        decoration:',1)
s=s.replace('isDense: true,\n        ),','isDense: true,\n          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),\n        ),',1)
s=s.replace('DropdownMenuItem(value: e, child: Text(text(e)))','DropdownMenuItem(value: e, child: Text(text(e), overflow: TextOverflow.ellipsis))',1)
s=s.replace('padding: const EdgeInsets.all(14),','padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),',1)

# Fetch real quantity and id.
s=s.replace("'receipt_number,consignee_name,consignee_phone,unloading_zone,special_note_auto,box_number',",
            "'id,receipt_number,consignee_name,consignee_phone,unloading_zone,special_note_auto,box_number,quantity',",1)
# Add quantity sum to result.
needle="""        result.add({
          'receipt': entry.key,
          'name': '${first['consignee_name'] ?? ''}'.trim(),"""
replacement="""        final quantity = entry.value.fold<num>(
          0,
          (sum, row) => sum + ((row['quantity'] as num?) ?? 0),
        );
        result.add({
          'receipt': entry.key,
          'name': '${first['consignee_name'] ?? ''}'.trim(),"""
s=s.replace(needle,replacement,1)
s=s.replace("          'count': entry.value.length,\n", "          'count': entry.value.length,\n          'quantity': quantity,\n",1)
# Display actual quantity, not row count.
s=s.replace("'${r['count']}건',", "'수량 ${r['quantity']}',",1)

# Add edit method before selector.
anchor='  Widget _selector<T>({'
method=r'''  Future<void> _editReceiptZone(Map<String, dynamic> row) async {
    final oldReceipt = '${row['receipt'] ?? ''}'.trim();
    final receiptController = TextEditingController(text: oldReceipt);
    final zoneController = TextEditingController(text: '${row['zone'] ?? ''}'.trim());
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${row['name'] ?? ''} 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: receiptController,
              decoration: const InputDecoration(labelText: '영수증 번호'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: zoneController,
              decoration: const InputDecoration(labelText: '구획(Zone)'),
            ),
            const SizedBox(height: 8),
            const Text(
              '현재 영수증 번호에 묶인 화물 전체에 동일하게 적용됩니다.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (save != true) return;
    final newReceipt = receiptController.text.trim();
    final newZone = zoneController.text.trim().toUpperCase();
    if (newReceipt.isEmpty || newZone.isEmpty) return;
    try {
      await SupabaseService.client
          .from('shipments')
          .update({
            'receipt_number': newReceipt,
            'unloading_zone': newZone,
          })
          .eq('route', _route!)
          .eq('shipment_year', _year!)
          .eq('voyage', _voyage!)
          .eq('receipt_number', oldReceipt)
          .isFilter('deletion_requested_at', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('영수증 번호 / Zone 수정 완료')),
        );
      }
      await _loadRows();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정 실패: $e')),
        );
      }
    }
  }

'''
if method.strip() not in s:
    if anchor not in s: raise SystemExit('customer selector anchor missing')
    s=s.replace(anchor,method+anchor,1)

# Add edit button to list tile.
old="""                          subtitle: Text(
                            [
                              if ('${r['phone']}'.isNotEmpty) '${r['phone']}',
                              'Zone ${r['zone']}',
                              '수량 ${r['quantity']}',
                              if (note.isNotEmpty) note,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );"""
new="""                          subtitle: Text(
                            [
                              if ('${r['phone']}'.isNotEmpty) '${r['phone']}',
                              'Zone ${r['zone']}',
                              '수량 ${r['quantity']}',
                              if (note.isNotEmpty) note,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '영수증 번호 / Zone 수정',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _editReceiptZone(r),
                          ),
                        );"""
if old not in s: raise SystemExit('customer ListTile anchor missing')
s=s.replace(old,new,1)

# Bottom summary bar before Expanded list ends: insert after list Expanded.
target="""            ),
          ],
        ),
      ),
    );"""
bottom="""            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '현재 항차 · 고객 ${_rows.length}명 · 총 수량 ${_rows.fold<num>(0, (sum, row) => sum + ((row['quantity'] as num?) ?? 0))}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );"""
if target not in s: raise SystemExit('customer bottom anchor missing')
s=s.replace(target,bottom,1)
p.write_text(s,encoding='utf-8')

f=(R/'lib/services/freight_service.dart').read_text(encoding='utf-8')
c=p.read_text(encoding='utf-8')
st=(R/'lib/screens/statement_preview_dialog.dart').read_text(encoding='utf-8')
q=(R/'lib/screens/quotation_preview_dialog.dart').read_text(encoding='utf-8')
checks=[
('BASE raw identity match',"_phoneMatches(phone, '${row['phone'] ?? ''}')" in f),
('customer no overflow helper','isExpanded: true' in c),
('customer actual quantity',"'quantity': quantity" in c),
('receipt zone edit','_editReceiptZone' in c and "'unloading_zone': newZone" in c),
('bottom summary','현재 항차 · 고객' in c),
('statement final right',st[st.find('final finalTop'):st.find('final payTop')].count('right: true')>=4),
('quotation 4/5 adjustment','totalW * .78' in q),
('quotation final right',q[q.find('final finalTop'):q.find('final payTop')].count('right: true')>=4),
]
print('PATCH190 VERIFY'); bad=[]
for n,o in checks:
 print(('[OK] ' if o else '[FAIL] ')+n)
 if not o: bad.append(n)
if bad: raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH190 VERIFIED OK')
