// Keep button actions, shape IDs, placement and formatting unchanged.
export const STATEMENT_BUTTON_LABEL = '모든 명세서 생성';
const action = /CreateInvoiceSheets02To100|CreateCurrentVoyageInvoiceSheets/;
const legacy = /^(?:(?:LKA|LKS)\s*0?2\s*[~～–—-]\s*100\s*(?:명세서\s*)?생성|현재\s*항차\s*고객\s*명세서\s*전체\s*생성)$/i;
const decode = value => value.replace(/&#x([0-9a-f]+);|&#(\d+);/gi,(_,hex,dec)=>String.fromCodePoint(parseInt(hex||dec,hex?16:10))).replace(/&amp;/g,'&').replace(/&nbsp;/g,' ');
export function renameStatementButtons(files) {
  let buttons=0;
  for(const [path,data] of Object.entries(files)) {
    if(!/\.(?:vml|xml)$/.test(path)||!/(?:drawings|customUI|ctrlProps)\//.test(path))continue;
    const xml=new TextDecoder().decode(data);
    let next=xml.replace(/<xdr:sp\b[\s\S]*?<\/xdr:sp>/g,shape=>{
      const label=decode([...shape.matchAll(/<a:t\b[^>]*>([\s\S]*?)<\/a:t>/g)].map(m=>m[1]).join('')).trim();
      if(label===STATEMENT_BUTTON_LABEL||(!action.test(shape)&&!legacy.test(label)))return shape;
      let first=true;
      const changed=shape.replace(/(<a:t\b[^>]*>)[\s\S]*?(<\/a:t>)/g,(_,open,close)=>{const text=first?STATEMENT_BUTTON_LABEL:'';first=false;return open+text+close;});
      if(changed!==shape)buttons++;
      return changed;
    }).replace(/<v:shape\b[\s\S]*?<\/v:shape>/g,shape=>{
      if(!action.test(shape))return shape;
      return shape.replace(/(<v:textbox\b[^>]*>)([\s\S]*?)(<\/v:textbox>)/,(_,open,body,close)=>{
        if(decode(body.replace(/<[^>]*>/g,'')).trim()===STATEMENT_BUTTON_LABEL)return open+body+close;
        let first=true;
        const changed=body.replace(/(^|>)([^<]+)(?=<|$)/g,(part,start,text)=>{if(!text.trim())return part;const label=first?STATEMENT_BUTTON_LABEL:'';first=false;return start+label;});
        if(first){buttons++;return open+STATEMENT_BUTTON_LABEL+body+close;}
        buttons++;return open+changed+close;
      });
    }).replace(/\blabel="([^"]*)"/g,(attribute,label)=>{if(!legacy.test(decode(label).trim()))return attribute;buttons++;return `label="${STATEMENT_BUTTON_LABEL}"`;});
    if(next!==xml)files[path]=new TextEncoder().encode(next);
  }
  return {buttons,changed:buttons>0};
}
