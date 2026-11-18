// Keep the old public macro name callable, but do not impose hard-coded fonts
// when opening/saving/printing a user-repaired template. New statements inherit
// their template sheet's formatting through Excel's existing sheet-copy action.
export function preserveTemplateHeaderFonts(source){
 const text=Array.from(source,b=>String.fromCharCode(b)).join('');
 const pattern=/Public Sub RestoreHeaderFontSizes\(\)[\s\S]*?End Sub/;
 if(!pattern.test(text)||text.includes('LK_PRESERVE_TEMPLATE_HEADERS_V1'))return null;
 const next=text.replace(pattern,'Public Sub RestoreHeaderFontSizes()\r\n    \' LK_PRESERVE_TEMPLATE_HEADERS_V1: retain uploaded cell formats.\r\nEnd Sub');
 return Uint8Array.from(next,c=>c.charCodeAt(0));
}
