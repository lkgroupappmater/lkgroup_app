from pathlib import Path

edge=Path.cwd()/"supabase"/"functions"/"export-shipment-excel"/"index.ts"
stmt=Path.cwd()/"lib"/"screens"/"statement_preview_dialog.dart"
if not edge.exists():
    raise SystemExit("export-shipment-excel/index.ts not found")
if not stmt.exists():
    raise SystemExit("statement_preview_dialog.dart not found")

s=edge.read_text(encoding="utf-8-sig")

old="""    const { data: shipments, error: shipmentError } = await admin
      .from('shipments')
      .select(
        'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,special_note_auto,received_at,created_at',
      )
      .eq('route', shipmentRouteLabel)
      .eq('shipment_year', shipmentYear)
      .eq('voyage', voyage)
      .is('deletion_requested_at', null)
      .order('box_number', { ascending: true })
      .order('id', { ascending: true });

    if (shipmentError) throw shipmentError;

    // Patch161: 실제 Excel 화물행은 DB의 현재 shipments를 source of truth로 사용합니다.
    // 특히 잠금 재업로드 변경요청이 pending/rejected인 경우 request payload의
    // incoming Excel 값을 출력에 섞지 않습니다.
    // 중앙 FreightService 정산값은 아래 voyage_settlement_snapshots에서 별도로 사용됩니다.
    const exportShipmentRows =
      (shipments ?? []) as Record<string, unknown>[];
"""

new="""    // Patch172A FAST EXPORT:
    // Flutter가 직전에 admin_excel_bulk_rows RPC로 읽은 현재 DB 화물을 그대로 전달하므로
    // 같은 항차의 shipments를 Edge에서 다시 한 번 읽는 왕복을 생략합니다.
    // 구버전 앱/직접 호출은 requestShipmentRows가 비어 있을 수 있으므로 그때만 DB fallback.
    let shipments: Record<string, unknown>[] = requestShipmentRows;
    if (shipments.length === 0) {
      const { data: shipmentRows, error: shipmentError } = await admin
        .from('shipments')
        .select(
          'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,special_note_auto,received_at,created_at',
        )
        .eq('route', shipmentRouteLabel)
        .eq('shipment_year', shipmentYear)
        .eq('voyage', voyage)
        .is('deletion_requested_at', null)
        .order('box_number', { ascending: true })
        .order('id', { ascending: true });
      if (shipmentError) throw shipmentError;
      shipments = (shipmentRows ?? []) as Record<string, unknown>[];
    }

    // requestShipmentRows 역시 같은 DB RPC의 현재값입니다.
    const exportShipmentRows = shipments;
"""

if s.count(old)!=1:
    raise SystemExit(f"Edge shipment block anchor expected 1, found {s.count(old)}. No file changed.")
s=s.replace(old,new,1)

# Adapt the original lookup loop from nullable DB response to the now-normalized list variable.
s=s.replace("(shipments ?? []).find((row) => Number(row.id) === id)", "shipments.find((row) => Number(row.id) === id)")

edge.write_text(s,encoding="utf-8")

d=stmt.read_text(encoding="utf-8-sig")
old2="""    _text(c, note, Rect.fromLTWH(8, sumTop + 38, leftW * .58 - 24, 112), 15.5,
        maxLines: 5);"""
new2="""    _text(
      c,
      note,
      Rect.fromLTWH(8, sumTop + 38, leftW * .58 - 24, 112),
      18,
      bold: true,
      center: true,
      maxLines: 5,
      lineHeight: 1.16,
    );"""
if d.count(old2)!=1:
    raise SystemExit(f"Remark painter anchor expected 1, found {d.count(old2)}. Edge not written? Edge already changed; restore via git if needed.")
d=d.replace(old2,new2,1)
stmt.write_text(d,encoding="utf-8")
print("Patch172A applied.")
