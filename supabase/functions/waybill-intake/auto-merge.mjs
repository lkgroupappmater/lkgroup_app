// Exact slash-expansion rules only. Spelling similarity remains a separate manual review.
const nk=v=>String(v??'').normalize('NFC').replace(/\s/g,'').toLowerCase();
const pk=v=>{const d=String(v??'').replace(/\D/g,'');return /^00856\d{8,10}$/.test(d)?'0'+d.slice(5):/^856\d{8,10}$/.test(d)?'0'+d.slice(3):/^0082\d{8,11}$/.test(d)?'0'+d.slice(4):/^82\d{8,11}$/.test(d)?'0'+d.slice(2):d;};
const tokens=(v,phone=false)=>[...new Set(String(v??'').split(phone?/[/,;\n\r]+/:/\//).map(phone?pk:nk).filter(Boolean))].sort();
const equal=(a,b)=>a.length===b.length&&a.every((v,i)=>v===b[i]);
const extension=(a,b)=>Math.abs(a.length-b.length)<=1&&(a.every(v=>b.includes(v))||b.every(v=>a.includes(v)));
export function autoPair(a,b){
 const an=tokens(a.name),bn=tokens(b.name),ap=tokens(a.phone,true),bp=tokens(b.phone,true);
 return !!(an.length&&bn.length&&ap.length&&bp.length&&[...ap,...bp].every(v=>v.length>=8&&v.length<=15)&&((equal(ap,bp)&&extension(an,bn))||(equal(an,bn)&&extension(ap,bp))));
}
export function unionContact(rows,field){
 const seen=new Set(),out=[],phone=field==='phone';
 for(const c of [...rows].sort((a,b)=>a.customer_no-b.customer_no))for(const raw of String(c[field]??'').split(phone?/[/,;\n\r]+/:/\//)){const key=(phone?pk:nk)(raw);if(key&&!seen.has(key)){seen.add(key);out.push(raw.trim());}}
 return out.join(' / ');
}
function components(rows){
 const remaining=new Set(rows),out=[];
 while(remaining.size){const group=[remaining.values().next().value];remaining.delete(group[0]);for(let i=0;i<group.length;i++)for(const c of remaining)if(autoPair(group[i],c)){group.push(c);remaining.delete(c);}if(group.length>1)out.push(group.sort((a,b)=>a.customer_no-b.customer_no));}
 return out;
}
export function autoCandidates(customers,aliases=[],rules=[],profiles=[]){
 const active=customers.filter(c=>!c.merged_into&&c.customer_no>2&&!/수취인\s*불명/.test(c.name||''));
 const protections=new Map(rules.map(r=>[r.name_key,r]));
 const rows=active.map(c=>{
  const names=new Set([nk(c.name),...aliases.filter(a=>a.customer_registry_id===c.id).map(a=>a.name_key)]),phones=tokens(c.phone,true);
  const separation_keys=[...new Set([...names].map(n=>protections.get(n)?.separation_key).filter(Boolean))];
  // Show all exact-name or complete-phone matches, including ambiguous delivery profiles.
  const delivery=profiles.filter(p=>p.active!==false&&(names.has(nk(p.customer_name))||names.has(nk(p.alternate_name))||tokens(String(p.phone_display||p.phone).replace(/\\r|\\n/g,' / '),true).some(p=>phones.includes(p))));
  const contexts=[...new Set(delivery.map(p=>[p.route_key,p.customer_name,p.delivery_type,p.local_company,p.destination_address,p.paid_by||'일반'].filter(Boolean).join(' · ')))];
  return {...c,customer_code:String(c.customer_no).padStart(3,'0'),separation_keys,delivery_contexts:contexts};
 });
 return components(rows).map(members=>{
  const protectedGroup=new Set(members.flatMap(c=>c.separation_keys)).size>1;
  const deliveryReview=members.some(c=>c.delivery_contexts.length>0);
  return {members,protected_group:protectedGroup,delivery_review:deliveryReview,default_selected:!protectedGroup&&!deliveryReview};
 });
}
export function previewAutoSelection(candidates,selection){
 if(!Array.isArray(selection)||!selection.length||selection.length>1000)throw Error('AUTO_SELECTION_INVALID');
 const all=new Map(candidates.flatMap(g=>g.members).map(c=>[c.id,c])),seen=new Set(),selected=[];
 for(const item of selection){if(!item||seen.has(item.id)||!all.has(item.id))throw Error('AUTO_SELECTION_INVALID');seen.add(item.id);const row=all.get(item.id);if(row.updated_at!==item.updated_at)throw Error('RECORD_CHANGED');selected.push(row);}
 // An unchecked bridge must never cause disconnected identities to merge.
 const groups=components(selected).map(members=>{
  if(members.length>100)throw Error('BULK_SELECTION_INVALID');
  if(new Set(members.flatMap(c=>c.separation_keys)).size>1)throw Error('SEPARATE_CUSTOMER_IDS');
  const name=unionContact(members,'name'),phone=unionContact(members,'phone');
  if(name.length>160||phone.length>160)throw Error('COMBINED_CONTACT_TOO_LONG');
  return {members,target_id:members[0].id,customer_code:members[0].customer_code,name,phone};
 });
 if(!groups.length)throw Error('AUTO_SELECTION_INVALID');
 const used=new Set(groups.flatMap(g=>g.members.map(c=>c.id)));
 return {groups,excluded_count:selected.length-used.size,merged_count:groups.reduce((n,g)=>n+g.members.length-1,0)};
}

// Display-only mapping: never resolve a shared phone to a different recipient name.
export function deliveryIdentityIndex(customers,aliases,profiles){
 const active=customers.filter(c=>!c.merged_into&&!/수취인\s*불명/.test(c.name||''));
 const byName=new Map();
 for(const c of active){const entries=[{name_key:nk(c.name),phone:c.phone},...aliases.filter(a=>a.customer_registry_id===c.id).map(a=>({name_key:a.name_key,phone:a.phone_key}))];for(const e of entries){const list=byName.get(e.name_key)||[];list.push({c,phones:tokens(e.phone,true)});byName.set(e.name_key,list);}}
 return profiles.map(p=>{
  const phones=tokens(String(p.phone_display||p.phone||'').replace(/\\r|\\n/g,' / '),true);let matches=[];
  for(const name of [p.customer_name,p.alternate_name]){const entries=byName.get(nk(name))||[];matches=[...new Map(entries.filter(e=>e.phones.some(v=>phones.includes(v))).map(e=>[e.c.id,e.c])).values()];if(matches.length)break;}
  return {id:p.id,customer_code:matches.length===1?String(matches[0].customer_no).padStart(3,'0'):null,identity_status:matches.length===1?'linked':matches.length?'ambiguous':'unmatched'};
 });
}
