// Discount identities only. Delivery/customer-registration matching is separate.
import {excelIdentity,recoveredName} from './receipt-order.mjs';
export const DISCOUNT_MATCH_VERSION = '2026-11-21.name-and-any-registered-phone-v3';
const lines = value => String(value ?? '').replace(/\\r\\n|\\n|\\r/g, '\n').replace(/[／]/g, '/');
export const discountNameKey = value => String(value ?? '').toLowerCase()
  .replace(/대표님|사장님|대표|사장|님/g, '').replace(/[\s\u00a0\-\/().,'"\[\]]/g, '');
export const discountNameParts = value => lines(value).split(/[/;|,\r\n()]+/).map(discountNameKey).filter(Boolean);
export function discountPhoneKey(value) {
  const digits = String(value ?? '').replace(/\D/g, '');
  if (/^00856\d{8,10}$/.test(digits)) return '0' + digits.slice(5);
  if (/^856\d{8,10}$/.test(digits)) return '0' + digits.slice(3);
  if (/^0082\d{8,11}$/.test(digits)) return '0' + digits.slice(4);
  if (/^82\d{8,11}$/.test(digits)) return '0' + digits.slice(2);
  return /^\d{8,15}$/.test(digits) ? digits : '';
}
export function discountPhoneTokens(value) {
  const raw = lines(value).trim();
  // Compatibility with old uploads which concatenated 11-digit Lao/Korean mobiles.
  const digits = raw.replace(/\D/g, '');
  if (!/[/;|,\r\n]/.test(raw) && digits.length > 15 && /^(?:0(?:20|10)\d{8})+$/.test(digits)) {
    return digits.match(/0(?:20|10)\d{8}/g);
  }
  return raw ? raw.split(/[/;|,\r\n]+/).map(discountPhoneKey) : [];
}
export function discountMemberGroups(name, phoneCount) {
  const groups = lines(name).split(/[/;|,\r\n]+/).map(discountNameParts).filter(g => g.length);
  const flat = groups.flat();
  // KOTRA: five names (including the parenthesized name) and five phones.
  // Two groups and two phones: a parenthesized alias shares its group's phone.
  return groups.length !== phoneCount && flat.length === phoneCount ? flat.map(n => [n]) : groups;
}
export function discountMatchRank(name, phone, rule) {
  if (['','XX'].includes(excelIdentity(name,phone))) return 9999;
  name=recoveredName(name,phone)??name;
  const inputNames = discountNameParts(name), inputPhones = discountPhoneTokens(phone).filter(Boolean);
  if (!inputNames.length || !inputPhones.length) return 9999;
  const phones = discountPhoneTokens(rule.phone_display || rule.phone);
  const members = discountMemberGroups(rule.customer_name, phones.length);
  const company = discountNameParts(rule.company_name);
  let rank = 9999;
  phones.forEach((number, index) => {
    if (!number || !inputPhones.includes(number)) return;
    if (company.some(n => inputNames.includes(n))) rank = Math.min(rank, 1);
    const eligible = members.length === 1 || phones.length === 1 ? members.flat()
      : members.length === phones.length ? members[index] : [];
    if (eligible.some(n => inputNames.includes(n))) rank = 0;
  });
  return rank;
}

const decode = b => new TextDecoder().decode(b);
const unescapeXml = s => String(s ?? '').replace(/&#(?:x([\da-f]+)|(\d+));/gi, (_,h,d) => String.fromCodePoint(parseInt(h || d,h?16:10)))
  .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');
export function discountWorkbookSource(files) {
  const workbook = decode(files['xl/workbook.xml']), rels = decode(files['xl/_rels/workbook.xml.rels']);
  const sheet = [...workbook.matchAll(/<sheet\b[^>]*>/g)].find(([tag]) => unescapeXml(tag.match(/\bname="([^"]*)"/)?.[1]) === 'Row data')?.[0];
  if (!sheet) return null;
  const rid = sheet.match(/\br:id="([^"]+)"/)?.[1];
  const relationship = [...rels.matchAll(/<Relationship\b[^>]*>/g)].find(([tag]) => tag.match(/\bId="([^"]+)"/)?.[1] === rid)?.[0];
  let path = relationship?.match(/\bTarget="([^"]+)"/)?.[1]?.replace(/^\//, '');
  if (!path) return null; if (!path.startsWith('xl/')) path = 'xl/' + path;
  const strings = [...decode(files['xl/sharedStrings.xml'] || new Uint8Array()).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m => [...m[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(t => unescapeXml(t[1])).join(''));
  const rows = new Map();
  for (const [xml,n] of decode(files[path]).matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g)) {
    const values = new Map();
    for (const [cell,col] of xml.matchAll(/<c\b[^>]*\br="([A-Z]+)\d+"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)) {
      const v = cell.match(/<v[^>]*>([\s\S]*?)<\/v>/)?.[1] || '';
      values.set(col, /\bt="s"/.test(cell) ? strings[Number(v)] || '' : /\bt="inlineStr"/.test(cell) ? [...cell.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(m => unescapeXml(m[1])).join('') : unescapeXml(v));
    }
    rows.set(Number(n), values);
  }
  const key = s => String(s || '').toLowerCase().replace(/[\s._-]/g, '');
  const isName = v => ['이름','성명','성함','고객명','name','customername'].includes(key(v));
  const isPhone = v => ['전화번호','연락처','휴대폰','휴대전화','tel','phone','telephone','contact','mobile','phonenumber'].includes(key(v));
  const isCompany = v => ['회사','회사명','소속','상호','업체명','company','companyname','customercompany'].includes(key(v));
  const isRate = v => ['할인','할인율','discount','discountrate'].includes(key(v));
  const column = n => {let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;};
  const rules=[];
  for (const [r,row] of rows) for(let c=0;c<32;c++) {
    if(!isName(row.get(column(c))))continue;
    let phone=-1,company=-1,rate=-1;
    for(let j=c+1;j<=c+6;j++){const v=row.get(column(j));if(isName(v))break;if(phone<0&&isPhone(v))phone=j;if(company<0&&isCompany(v))company=j;if(rate<0&&isRate(v))rate=j;}
    if(phone<0||rate<0)continue;
    for(let n=r+1;rows.has(n);n++){
      const data=rows.get(n), name=data.get(column(c))?.trim();if(!name)break;
      rules.push({customer_name:name,company_name:company<0?'':data.get(column(company))||'',phone_display:data.get(column(phone))||'',excel_source_row:n,
        refs:{name:column(c)+n,company:company<0?null:column(company)+n,phone:column(phone)+n,rate:column(rate)+n}});
    }
  }
  return {path,rows,rules};
}
