const fs = require('fs');

const p = 'supabase/functions/export-shipment-excel/index.ts';
let s = fs.readFileSync(p, 'utf8');

const old1 = "    const type = d ? (String(d.delivery_type ?? '') === 'city' ? 'city' : (paidBy.includes('?쒓뎅') || paidBy.includes('korea') || paidBy.includes('prepaid') ? 'province_prepaid_kr' : 'province')) : '';";
const old2 = "    const delivery = d ? [d.source_no ? `(${d.source_no})` : '', d.alternate_name || d.customer_name || name, d.phone_display || d.phone || phone, d.local_company, d.destination_address].filter(Boolean).join(', ') : '';";
const old3 = "      .select('source_no,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes')";
const old4 = "      .eq('active', true);";

for (const [n, x] of [['type', old1], ['delivery', old2], ['select', old3]]) {
  if (!s.includes(x)) throw new Error(`exporter target not found: ${n}`);
}
const selectPos = s.indexOf(old3);
const activePos = s.indexOf(old4, selectPos);
if (activePos < 0) throw new Error('exporter active target not found');

const new1 = `    const koreaMarker =
      paidBy.includes('\\uD55C\\uAD6D') || paidBy.includes('korea');
    const prepaidMarker =
      paidBy.includes('\\uC120\\uACB0\\uC81C') ||
      paidBy.includes('\\uC120\\uBD88') ||
      paidBy.includes('prepaid');
    const isKoreaPrepaid = koreaMarker && prepaidMarker;
    const type = d ? (String(d.delivery_type ?? '') === 'city' ? 'city' : (isKoreaPrepaid ? 'province_prepaid_kr' : 'province')) : '';`;
const new2 = "    const delivery = d ? [d.source_no ? `(${d.source_no})` : '', d.alternate_name || d.customer_name || name, d.phone_display || d.phone || phone, d.local_company, d.destination_address, d.paid_by].filter(Boolean).join(', ') : '';";
const new3 = "      .select('source_no,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred')";

s = s.replace(old1, new1).replace(old2, new2).replace(old3, new3);
const activePos2 = s.indexOf(old4, s.indexOf(new3));
s = s.slice(0, activePos2) +
    "      .eq('active', true)\n      .order('preferred', { ascending: false })\n      .order('source_no', { ascending: true });" +
    s.slice(activePos2 + old4.length);

fs.writeFileSync(p, s, 'utf8');
