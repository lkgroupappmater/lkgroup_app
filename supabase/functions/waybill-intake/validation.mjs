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
    ...(Object.hasOwn(w,'carrier_text')?{carrier_text:String(w.carrier_text??'').trim().slice(0,160)}:{}),
    ...(Object.hasOwn(w,'tracking_text')?{tracking_text:String(w.tracking_text??'').trim().slice(0,160)}:{}),
  }));
  for(const d of drafts){
    // Literal logo evidence takes precedence over the model's enum guess.
    // Do not infer a courier from an unbranded 13-digit number.
    if(Object.hasOwn(d,'carrier_text')){
      const brand=d.carrier_text.toUpperCase();
      const brands=[['ANS',/\bANOUSITH\b|\bAN[ZS]\b/],['LAOPOST',/\bLAO\s*POST\b|\bPOST[\s-]*X\b/],['HAL',/\bHOUNG\s*ALOUN\b|\bHAL\b/],['MIXAY',/\bMIXAY\b/],['JT',/\bJ\s*&\s*T\b|\bJ\s*AND\s*T\b/]].filter(([,pattern])=>pattern.test(brand));
      const evidence=brands.length===1?brands[0][0]:'';
      if(d.carrier!==evidence)d.note='Carrier checked against the printed brand. '+d.note;
      d.carrier=evidence;
      if(!evidence)d.note='Carrier logo/name is unclear. Select the carrier after checking the photo. '+d.note;
    }
    if(/(?:included|copied|taken|provided).{0,70}(?:instruction|example)|per (?:developer )?instruction|not actually visible/i.test(d.note)){
      d.tracking_number='';d.note='Tracking number was not grounded in the image. Read the original label again.';
    }
    if(Object.hasOwn(d,'tracking_text')){
      const printed=d.tracking_text.replace(/\s/g,'').toUpperCase();
      const right=d.carrier==='ANS'?/^\d+[|｜](\d{13})$/.exec(printed):null;
      if(right)d.tracking_number=right[1];
      else if(d.tracking_number&&!printed.split(/[|｜]/).includes(d.tracking_number)){
        d.tracking_number='';d.note='The complete tracking number could not be confirmed from the printed barcode caption.';
      }
    }
    d.note=d.note.slice(0,240);
  }
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
