export const MAX_FILES = 50;
export const MAX_FILE_BYTES = 5 * 1024 * 1024;
export const MAX_TOTAL_BYTES = 250 * 1024 * 1024;
export const CARRIER_CODES = ['HAL', 'ANS', 'MIXAY', 'JT', 'LAOPOST'];
export function validateFiles(files) {
  if (!Array.isArray(files) || !files.length || files.length > MAX_FILES) throw Error('INVALID_BATCH');
  let total = 0;
  return files.map(f => {
    if (!f || !Number.isSafeInteger(f.size) || f.size < 13 || f.size > MAX_FILE_BYTES) throw Error('FILE_TOO_LARGE');
    total += f.size;
    if (total > MAX_TOTAL_BYTES) throw Error('FILE_TOO_LARGE');
    const ext = String(f.name ?? '').split('.').pop().toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].includes(ext)) throw Error('INVALID_IMAGE');
    return {name: String(f.name).slice(0, 180), size: f.size, ext: ext === 'jpeg' ? 'jpg' : ext};
  });
}
export function imageMime(bytes) {
  if (!bytes || bytes.length < 13 || bytes.length > MAX_FILE_BYTES) throw Error('INVALID_IMAGE');
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'image/jpeg';
  if ([137,80,78,71,13,10,26,10].every((v,i) => bytes[i] === v)) return 'image/png';
  if (String.fromCharCode(...bytes.slice(0,4)) === 'RIFF' && String.fromCharCode(...bytes.slice(8,12)) === 'WEBP') return 'image/webp';
  throw Error('INVALID_IMAGE');
}
export function normalizeDrafts(data) {
  if (!data || !Array.isArray(data.waybills) || data.waybills.length > MAX_FILES) throw Error('OCR_FAILED');
  const drafts = data.waybills.map(w => ({
    tracking_number: String(w.tracking_number ?? '').replace(/\s/g, '').toUpperCase().slice(0,40),
    carrier: CARRIER_CODES.includes(w.carrier) ? w.carrier : '',
    receiver_name: String(w.receiver_name ?? '').trim().slice(0,160),
    receiver_phone: String(w.receiver_phone ?? '').trim().slice(0,40),
    note: String(w.note ?? '').trim().slice(0,240),
  }));
  // Anousith labels show account | full tracking, plus a large six-digit suffix.
  for(const d of drafts) if(d.carrier==='ANS'){
    const split=/^\d+[|｜]([0-9]{13})$/.exec(d.tracking_number);
    if(split)d.tracking_number=split[1];
  }
  const fullAns=drafts.filter(d=>d.carrier==='ANS'&&/^\d{13}$/.test(d.tracking_number));
  const seen=new Set();
  return drafts.filter(d=>!(d.carrier==='ANS'&&fullAns.length&&(
    (/^\d{6}$/.test(d.tracking_number)&&fullAns.some(full=>full.tracking_number.endsWith(d.tracking_number)))||
    (/^\d{7}$/.test(d.tracking_number)&&/internal|account|secondary|short number under barcode/i.test(d.note))
  ))).map(d=>{
    if(d.carrier==='ANS'&&!/^\d{13}$/.test(d.tracking_number)){
      d.tracking_number='';d.note='Read the complete 13-digit Anousith number to the right of | below the barcode. The left account number and large six-digit suffix are not waybills.';
    }
    return d;
  }).filter(d=>{if(d.carrier!=='ANS'||!d.tracking_number)return true;const key=d.carrier+':'+d.tracking_number;if(seen.has(key))return false;seen.add(key);return true;});
}
export function validateReviewed(entries, files) {
  if (!Array.isArray(entries) || !entries.length || entries.length > MAX_FILES) throw Error('INVALID_BATCH');
  const seen = new Set();
  for (const e of entries) {
    if (e.confirmed !== true) throw Error('REVIEW_REQUIRED');
    if (e.is_reference_photo !== true) {
      if (!CARRIER_CODES.includes(e.carrier) || !/^[A-Z0-9][A-Z0-9-]{5,39}$/.test(e.tracking_number ?? '')) throw Error('INVALID_TRACKING');
      if(e.carrier==='ANS'&&!/^\d{13}$/.test(e.tracking_number))throw Error('ANS_TRACKING_REQUIRED');
      const key = e.carrier + ':' + e.tracking_number;
      if (seen.has(key)) throw Error('DUPLICATE_TRACKING');
      seen.add(key);
    }
    if (!Array.isArray(e.file_ids) || !e.file_ids.length || e.file_ids.some(id => !files.some(f => f.id === id && f.verified_at))) throw Error('INVALID_IMAGE');
  }
  return entries;
}
