from pathlib import Path
R=Path.cwd()

def read(rel):
    p=R/rel
    if not p.exists(): raise SystemExit(f'missing: {rel}')
    return p,p.read_text(encoding='utf-8-sig')

# ---------- customer list final tuning ----------
p,s=read('lib/screens/customer_list_management_screen.dart')

# 20% down from Patch193D values.
repls=[
("_paintText(c,heads[i],r,18,bold:true);","_paintText(c,heads[i],r,15,bold:true);"),
("_paintText(c,boxLines[b],br,22,bold:false,align:TextAlign.center);",
 "_paintText(c,boxLines[b],br,18,bold:false,align:TextAlign.center);"),
("? 30.0", "? 24.0"),
(": (i==5 ? 24.0 : 28.0)", ": (i==5 ? 19.0 : 22.0)"),
]
for a,b in repls:
    if a in s: s=s.replace(a,b,1)

# Give box-number column more width.
for old in [
"final xs=<double>[left,145,390,505,760,840,right];",
"final xs=<double>[left,145,390,505,760,840,right];"
]:
    if old in s:
        s=s.replace(old,"final xs=<double>[left,145,370,480,790,860,right];",1)
        break

# Park/LKS100: hide box numbers and quantity in print only.
old="""      final boxLines=_boxLines(row);
      final rowH=unitH*boxLines.length;
      final delivery='${row['delivery']??''}';
      final values=<String>[
        '${row['receipt']??''}',
        '${row['name']??''}',
        '${row['zone']??''}',
        '',
        '${row['quantity']??''}',
        delivery,
      ];"""
new="""      final receiptText='${row['receipt']??''}'.trim();
      final nameText='${row['name']??''}'.replaceAll(RegExp(r'\\s+'),'');
      final isPark=nameText.startsWith('박성호') ||
          RegExp(r'(^|[^0-9])100([^0-9]|$)').hasMatch(receiptText);
      final boxLines=isPark ? const <String>[''] : _boxLines(row);
      final rowH=unitH*boxLines.length;
      final delivery='${row['delivery']??''}';
      final values=<String>[
        receiptText,
        '${row['name']??''}',
        '${row['zone']??''}',
        '',
        isPark ? '' : '${row['quantity']??''}',
        delivery,
      ];"""
if old not in s: raise SystemExit('customer print row anchor missing')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')

# ---------- ShipmentService manual uncertainty ----------
p,s=read('lib/services/shipment_service.dart')
anchor="""  Future<void> updateRow(String id, Map<String, dynamic> changes) async {
    if (!SupabaseConfig.isConfigured || changes.isEmpty) return;
    await SupabaseService.client.from('shipments').update(changes).eq('id', id);
  }
"""
if anchor not in s: raise SystemExit('ShipmentService updateRow anchor missing')
addition=anchor+"""
  Future<void> setManualUncertain(String id, bool value) async {
    if (!SupabaseConfig.isConfigured) return;
    final numericId = int.tryParse(id.trim());
    if (numericId == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client
        .from('shipments')
        .update({'manual_uncertain': value})
        .eq('id', numericId);
  }

  Future<List<Map<String, dynamic>>> listManualUncertainForAdmin() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client
        .from('shipments')
        .select()
        .eq('manual_uncertain', true)
        .order('shipment_year', ascending: false)
        .order('voyage', ascending: false)
        .order('box_number');
    return List<Map<String, dynamic>>.from(raw as List);
  }
"""
s=s.replace(anchor,addition,1)
p.write_text(s,encoding='utf-8')

# ---------- Cargo management '?' toggle ----------
p,s=read('lib/screens/cargo_management_screen.dart')

# Add toggle method before lock method.
lock_anchor="  Future<void> _toggleShipmentLock(Map<String, dynamic> item) async {"
if lock_anchor not in s: raise SystemExit('cargo lock method anchor missing')
method="""  Future<void> _toggleManualUncertain(Map<String, dynamic> item) async {
    if (!_isAdmin || _busy) return;
    final id='${item['id']}';
    final current=item['manual_uncertain']==true;
    setState(()=>_busy=true);
    try {
      await ShipmentService.instance.setManualUncertain(id,!current);
      if(!mounted)return;
      setState(()=>item['manual_uncertain']=!current);
      _message(!current
          ? '불확실 화물로 표시했습니다. 변경 승인 관리에서 확인할 수 있습니다.'
          : '불확실 표시를 해제했습니다.');
    } catch(error) {
      _message('불확실 표시 처리 실패: $error');
    } finally {
      if(mounted)setState(()=>_busy=false);
    }
  }

"""
s=s.replace(lock_anchor,method+lock_anchor,1)

# Add ? button immediately after the existing admin lock container.
needle="""                          ),
                        ),
                      ),"""
# Find the occurrence nearest lock tooltip.
pos=s.find("item['data_locked'] == true ? '잠금 해제' : '잠금'")
if pos<0: raise SystemExit('cargo lock UI anchor missing')
end=s.find(needle,pos)
if end<0: raise SystemExit('cargo lock container end missing')
end += len(needle)
button="""
                    if (_isAdmin) const SizedBox(height: 8),
                    if (_isAdmin)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: item['manual_uncertain'] == true
                              ? Colors.yellow
                              : Colors.white,
                          border: Border.all(color: Colors.black54),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: item['manual_uncertain'] == true
                              ? '불확실 표시 해제'
                              : '불확실 화물 표시',
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () => _toggleManualUncertain(item),
                          icon: const Icon(
                            Icons.question_mark,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),"""
s=s[:end]+button+s[end:]
p.write_text(s,encoding='utf-8')

# ---------- Approval management: merge manual uncertainty ----------
p,s=read('lib/screens/change_approval_screen.dart')
old="""      final incomplete =
          await UnknownRecipientService.instance.listIncompleteForAdmin();"""
new="""      final incomplete =
          await UnknownRecipientService.instance.listIncompleteForAdmin();
      final manualUncertain =
          await ShipmentService.instance.listManualUncertainForAdmin();
      final incompleteById=<String,Map<String,dynamic>>{
        for(final row in incomplete)
          '${row['shipment_id'] ?? row['id'] ?? ''}': row,
      };
      for(final row in manualUncertain){
        final id='${row['id'] ?? ''}';
        if(id.isEmpty)continue;
        final existing=incompleteById[id];
        if(existing!=null){
          existing['manual_uncertain']=true;
          existing['reason'] ??= '관리자 수동 불확실 표시';
        }else{
          final copy=Map<String,dynamic>.from(row);
          copy['shipment_id']=id;
          copy['manual_uncertain']=true;
          copy['reason']='관리자 수동 불확실 표시';
          incomplete.add(copy);
          incompleteById[id]=copy;
        }
      }"""
if old not in s: raise SystemExit('approval incomplete load anchor missing')
s=s.replace(old,new,1)

# When approval/review completes, clear manual flag. Both edit and lock actions.
old="""        await UnknownRecipientService.instance.reviewIncomplete(
          shipmentId: '${row['shipment_id'] ?? row['id'] ?? ''}',"""
new="""        final reviewedShipmentId='${row['shipment_id'] ?? row['id'] ?? ''}';
        await UnknownRecipientService.instance.reviewIncomplete(
          shipmentId: reviewedShipmentId,"""
if old not in s: raise SystemExit('approval review anchor missing')
s=s.replace(old,new,1)

anchor="""          lock: lock,
        );
        if (mounted) {"""
new="""          lock: lock,
        );
        if(row['manual_uncertain']==true){
          await ShipmentService.instance.setManualUncertain(
            reviewedShipmentId,
            false,
          );
        }
        if (mounted) {"""
if anchor not in s: raise SystemExit('approval clear flag anchor missing')
s=s.replace(anchor,new,1)

# Existing card already places buttons on the right in a single top Row.
# Replace Wrap with Row so the two buttons stay in one horizontal line.
card_pos=s.find("Widget _incompleteCard")
if card_pos<0: raise SystemExit('incomplete card missing')
wrap_pos=s.find("                Wrap(",card_pos)
if wrap_pos>=0:
    s=s[:wrap_pos]+s[wrap_pos:].replace("                Wrap(\n                  spacing: 4,\n                  runSpacing: 2,\n                  children: [",
                                        "                Row(\n                  mainAxisSize: MainAxisSize.min,\n                  children: [",1)
    # add spacing between the two buttons using SizedBox before FilledButton
    after= s.find("child: const Text(\n                        '확인/수정'",card_pos)
    fill=s.find("                    FilledButton.icon(",after)
    if fill>=0:
        s=s[:fill]+"                    const SizedBox(width: 6),\n"+s[fill:]
p.write_text(s,encoding='utf-8')

# ---------- verification ----------
checks={}
u=(R/'lib/screens/customer_list_management_screen.dart').read_text(encoding='utf-8')
checks['customer fonts -20%']='? 24.0' in u and 'i==5 ? 19.0 : 22.0' in u and 'boxLines[b],br,18' in u
checks['box wider']='[left,145,370,480,790,860,right]' in u
checks['Park print hides boxes/qty']="final isPark=" in u and "isPark ? '' : '${row['quantity']??''}'" in u

u=(R/'lib/services/shipment_service.dart').read_text(encoding='utf-8')
checks['manual uncertainty service']='setManualUncertain' in u and 'listManualUncertainForAdmin' in u

u=(R/'lib/screens/cargo_management_screen.dart').read_text(encoding='utf-8')
checks['question toggle']='Icons.question_mark' in u and '_toggleManualUncertain' in u and 'Colors.yellow' in u

u=(R/'lib/screens/change_approval_screen.dart').read_text(encoding='utf-8')
checks['approval only queue']='listManualUncertainForAdmin' in u and "관리자 수동 불확실 표시" in u
checks['approval clears toggle']="setManualUncertain" in u and "reviewedShipmentId" in u
checks['approval buttons horizontal']="mainAxisSize: MainAxisSize.min" in u and "'확인/수정'" in u and "'확정/잠금'" in u

print('PATCH194 VERIFY')
bad=[]
for n,o in checks.items():
    print(('[OK] ' if o else '[FAIL] ')+n)
    if not o: bad.append(n)
if bad: raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH194 VERIFIED OK')
