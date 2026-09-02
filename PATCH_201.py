from pathlib import Path
import sys


def replace_once(source: str, old: str, new: str, label: str) -> str:
    old_count = source.count(old)
    if old_count == 1:
        return source.replace(old, new, 1)
    if old_count == 0 and new in source:
        return source
    raise SystemExit(f"unexpected source state for {label}: old={old_count}")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: PATCH_201.py <project-root>")

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
    original = source

    source = replace_once(
        source,
        """  if (!prefix) return shipments;

  // 이름 + 전화번호가 같으면 같은 영수번호를 사용합니다.
""",
        """  if (!prefix) return shipments;

  const unknownReceipt =
    routeKey === 'kr_la_sea' || routeKey === 'kr_la_air'
      ? `${prefix} XX`
      : `${prefix}XX`;
  const normalizedShipments = shipments.map((shipment) =>
    shipment.recipient_unknown === true
      ? {
          ...shipment,
          receipt_number: unknownReceipt,
          unloading_zone: 'F',
        }
      : shipment
  );

  // 이름 + 전화번호가 같으면 같은 영수번호를 사용합니다.
""",
        "unknown receipt normalization",
    )

    source = replace_once(
        source,
        """  // 기존 영수번호가 있으면 우선 그대로 유지하고 다음 번호 계산.
  for (const shipment of shipments) {
""",
        """  // 기존 영수번호가 있으면 우선 그대로 유지하고 다음 번호 계산.
  for (const shipment of normalizedShipments) {
""",
        "normalized receipt scan",
    )

    source = replace_once(
        source,
        r"""    const recoverableXx = hasIdentity && /\bXX\s*$/i.test(existing);
""",
        r"""    const recoverableXx =
      shipment.recipient_unknown !== true &&
      hasIdentity &&
      /\bXX\s*$/i.test(existing);
""",
        "true unknown scan guard",
    )

    source = replace_once(
        source,
        r"""  return shipments.map((shipment) => {
    const existing = String(shipment.receipt_number ?? '').trim();
    const name = String(shipment.consignee_name ?? '').trim();
    const phone = normalizePhone(shipment.consignee_phone);
    const recoverableXx = name !== '' && phone !== '' && /\bXX\s*$/i.test(existing);
""",
        r"""  return normalizedShipments.map((shipment) => {
    const existing = String(shipment.receipt_number ?? '').trim();
    const name = String(shipment.consignee_name ?? '').trim();
    const phone = normalizePhone(shipment.consignee_phone);
    const recoverableXx =
      shipment.recipient_unknown !== true &&
      name !== '' &&
      phone !== '' &&
      /\bXX\s*$/i.test(existing);
""",
        "true unknown allocation guard",
    )

    source = replace_once(
        source,
        r'''  const styleMatch = attrs.match(/\\bs="([^"]+)"/);
''',
        r'''  const styleMatch = attrs.match(/\bs="([^"]+)"/);
''',
        "customer Zone cell style",
    )

    source = replace_once(
        source,
        r"""    if (isFixed102) {
      nextRow = updateCell(nextRow, rowNumber, 'C', '102', 'text');
""",
        r"""    if (/\bxx\s*$/i.test(receipt)) {
      nextRow = updateCell(nextRow, rowNumber, 'C', 'F', 'text');
    } else if (isFixed102) {
      nextRow = updateCell(nextRow, rowNumber, 'C', '102', 'text');
""",
        "XX customer Zone",
    )

    source = replace_once(
        source,
        "id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,special_note_auto,received_at,created_at",
        "id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,recipient_unknown,notes,special_note_auto,received_at,created_at",
        "recipient_unknown query",
    )

    source = replace_once(
        source,
        r"""      const originalReceipt = String(original?.receipt_number ?? '').trim();
      const originalWasRecoverableXx =
        /\bXX\s*$/i.test(originalReceipt) &&
        String(shipment.consignee_name ?? '').trim() !== '' &&
        normalizePhone(shipment.consignee_phone) !== '' &&
        !/\bXX\s*$/i.test(receipt);
      if (id && receipt && (!originalReceipt || originalWasRecoverableXx)) {
        const { error: receiptUpdateError } = await admin
          .from('shipments')
          .update({ receipt_number: receipt })
""",
        r"""      const originalReceipt = String(original?.receipt_number ?? '').trim();
      const originalZone = String(original?.unloading_zone ?? '').trim();
      const originalWasRecoverableXx =
        /\bXX\s*$/i.test(originalReceipt) &&
        String(shipment.consignee_name ?? '').trim() !== '' &&
        normalizePhone(shipment.consignee_phone) !== '' &&
        !/\bXX\s*$/i.test(receipt);
      const trueUnknownNeedsRepair =
        shipment.recipient_unknown === true &&
        (originalReceipt !== receipt || originalZone !== 'F');
      if (
        id &&
        receipt &&
        (!originalReceipt || originalWasRecoverableXx || trueUnknownNeedsRepair)
      ) {
        const updateValues = shipment.recipient_unknown === true
          ? { receipt_number: receipt, unloading_zone: 'F' }
          : { receipt_number: receipt };
        const { error: receiptUpdateError } = await admin
          .from('shipments')
          .update(updateValues)
""",
        "persist true unknown repair",
    )

    if source == original:
        print("Patch201 already applied")
        return 0

    with target.open("w", encoding="utf-8", newline="") as handle:
        handle.write(source)

    print("Patch201 applied: Zone style preserved and true unknown receipts use XX/F")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
