export const MAX_PHOTOS = 10;
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
export const MAX_PHOTOS_BYTES = 15 * 1024 * 1024;
export const MAX_REQUEST_BYTES = 22 * 1024 * 1024;
export function decodePhotos(body) {
  const items = body.photos ?? (body.photo ? [body.photo] : []);
  if (!Array.isArray(items)) throw Error('INVALID_IMAGE');
  if (items.length > MAX_PHOTOS) throw Error('TOO_MANY_PHOTOS');
  let total = 0;
  return items.map(photo => {
    if (typeof photo?.base64 !== 'string') throw Error('INVALID_IMAGE');
    if (photo.base64.length > 6990508) throw Error('FILE_TOO_LARGE');
    let bytes;
    try { bytes = Uint8Array.from(atob(photo.base64), c => c.charCodeAt(0)); }
    catch { throw Error('INVALID_IMAGE'); }
    total += bytes.length;
    if (bytes.length > MAX_PHOTO_BYTES || total > MAX_PHOTOS_BYTES) throw Error('FILE_TOO_LARGE');
    if (bytes.length <= 12) throw Error('INVALID_IMAGE');
    const png = bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71;
    const jpg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
    const webp = String.fromCharCode(...bytes.slice(0,4)) === 'RIFF' && String.fromCharCode(...bytes.slice(8,12)) === 'WEBP';
    if (!png && !jpg && !webp) throw Error('INVALID_IMAGE');
    return {bytes, ext:png?'png':jpg?'jpg':'webp', mime:png?'image/png':jpg?'image/jpeg':'image/webp'};
  });
}
export async function readBody(req) {
  if (Number(req.headers.get('Content-Length') ?? 0) > MAX_REQUEST_BYTES) throw Error('FILE_TOO_LARGE');
  const reader = req.body?.getReader(); if (!reader) return '';
  const decoder = new TextDecoder(); let size=0, result='';
  try {
    while (true) {
      const {done,value}=await reader.read(); if(done) break;
      size+=value.byteLength;if(size>MAX_REQUEST_BYTES)throw Error('FILE_TOO_LARGE');
      result+=decoder.decode(value,{stream:true});
    }
    return result+decoder.decode();
  } finally { await reader.cancel().catch(()=>{}); }
}
