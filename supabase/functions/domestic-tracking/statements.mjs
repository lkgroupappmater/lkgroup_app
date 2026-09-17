// Shared by the web and app API. LK receipts are not inbound invoice numbers.
export function receiptKey(value) {
  const key = String(value ?? '').trim().toUpperCase().replace(/\s/g, '');
  const match = /^([A-Z]*)(\d+)$/.exec(key);
  return match ? match[1] + match[2].replace(/^0+(?=\d)/, '') : key;
}
export function statementInput(body = {}) {
  body = body ?? {};
  const route = String(body.route ?? '').trim();
  const voyage = String(body.voyage ?? '').trim();
  const receipt_number = String(body.receipt_number ?? body.statement_number ?? '').trim();
  const shipment_year = Number(body.shipment_year ?? body.year);
  if (!route || route.length > 160 || !voyage || voyage.length > 40 ||
      !/^[A-Za-z0-9][A-Za-z0-9 .\/_-]{0,79}$/.test(receipt_number) ||
      !Number.isInteger(shipment_year) || shipment_year < 1900 || shipment_year > 2200) {
    throw new Error('INVALID_STATEMENT');
  }
  return {route, shipment_year, voyage, receipt_number};
}
export function referenceInput(body = {}) {
  body = body ?? {};
  const reference_type = String(body.reference_type ?? '');
  const reference_number = String(body.reference_number ?? '').trim().toUpperCase().replace(/\s/g, '');
  if (!['ecommerce', 'local'].includes(reference_type) ||
      !/^[A-Z0-9][A-Z0-9./_-]{0,79}$/.test(reference_number)) throw new Error('INVALID_REFERENCE');
  return {reference_type, reference_number};
}
export function rowStatement(row) {
  if (row.link_scope === 'statement') return {route: row.link_route,
    shipment_year: row.link_year, voyage: row.link_voyage, receipt_number: row.link_receipt_number};
  if (row.statement_route) return {route: row.statement_route,
    shipment_year: row.statement_year, voyage: row.statement_voyage, receipt_number: row.statement_receipt};
  return null;
}
export function canManageParcel(profile, row = null) {
  return ['admin', 'staff'].includes(profile.role) ||
    (profile.role === 'partner' && (!row || row.created_by === profile.id));
}
export async function mapLimited(rows, fn, limit = 4) {
  const output = new Array(rows.length); let next = 0;
  await Promise.all(Array.from({length: Math.min(limit, rows.length)}, async () => {
    while (next < rows.length) { const index = next++; output[index] = await fn(rows[index]); }
  }));
  return output;
}
