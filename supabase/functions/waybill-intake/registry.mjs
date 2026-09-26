// Candidate flags are review hints, never automatic identity merges.
export function oneEditApart(a, b, minimum = 2) {
  if (!a || !b || Math.min(a.length,b.length)<minimum || Math.abs(a.length-b.length)>1 || a===b) return false;
  let i=0,j=0,edits=0;
  while(i<a.length&&j<b.length){if(a[i]===b[j]){i++;j++;continue;}if(++edits>1)return false;if(a.length>=b.length)i++;if(b.length>=a.length)j++;}
  return edits+(i<a.length||j<b.length?1:0)===1;
}
export function registrySummary(customers, sources) {
  const active=customers.filter(c=>!c.merged_into), byId=new Map(active.map(c=>[c.id,{...c,customer_code:String(c.customer_no).padStart(3,'0'),source_count:0,mismatch_count:0,duplicates:[]} ]));
  for(const s of sources){const c=byId.get(s.customer_registry_id);if(c){c.source_count++;if(s.mismatch)c.mismatch_count++;}}
  for(let i=0;i<active.length;i++)for(let j=i+1;j<active.length;j++){
    const a=active[i],b=active[j],reasons=[];
    if(a.name_key&&a.name_key===b.name_key)reasons.push('same_name');
    if(a.phone_key&&a.phone_key===b.phone_key)reasons.push('same_phone');
    if(oneEditApart(a.name_key,b.name_key))reasons.push('similar_name');
    if(oneEditApart(a.phone_key,b.phone_key,8))reasons.push('similar_phone');
    if(reasons.length){byId.get(a.id).duplicates.push({id:b.id,reasons});byId.get(b.id).duplicates.push({id:a.id,reasons});}
  }
  const rows=[...byId.values()].map(c=>({...c,conflict:!c.phone_key||c.duplicates.length>0,mismatch:c.mismatch_count>0}));
  return {rows,summary:{customers:rows.length,duplicate_customers:rows.filter(c=>c.duplicates.length).length,mismatch_customers:rows.filter(c=>c.mismatch).length,mismatch_sources:rows.reduce((n,c)=>n+c.mismatch_count,0),missing_phone:rows.filter(c=>!c.phone_key).length}};
}
export async function mapLimit(items, limit, fn) {
  const output=new Array(items.length);let next=0;
  await Promise.all(Array.from({length:Math.min(limit,items.length)},async()=>{while(next<items.length){const i=next++;output[i]=await fn(items[i],i);}}));
  return output;
}
