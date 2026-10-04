const encode=s=>new TextEncoder().encode(s),decode=b=>new TextDecoder().decode(b);
const binary=b=>Array.from(b,c=>String.fromCharCode(c)).join('');
const bytes=s=>Uint8Array.from(s,c=>c.charCodeAt(0));
const allAction=/CreateInvoiceSheets02To100|CreateCurrentVoyageInvoiceSheets/;
const specialAction=/CreateBulkSpecialInvoiceSheets/;
const label=s=>[...s.matchAll(/<a:t\b[^>]*>([\s\S]*?)<\/a:t>/g)].map(m=>m[1]).join('').replace(/\s/g,'');
function font36(xml){return xml.replace(/<a:(?:rPr|defRPr|endParaRPr)\b[^>]*>/g,tag=>/\bsz="/.test(tag)?tag.replace(/\bsz="\d+"/,'sz="3600"'):tag.replace(/\/?\s*>$/,m=>' sz="3600"'+m));}

export function fitStatementButtons(files){
 let changed=0;
 for(const [path,data] of Object.entries(files)){
  if(!/^xl\/drawings\/[^/]+\.(xml|vml)$/.test(path))continue;
  const xml=decode(data);let next=xml;
  if(path.endsWith('.xml')){
   next=xml.replace(/<xdr:twoCellAnchor\b[\s\S]*?<\/xdr:twoCellAnchor>/g,anchor=>{
    const shape=anchor.match(/<xdr:sp\b[\s\S]*?<\/xdr:sp>/)?.[0];if(!shape)return anchor;
    const special=specialAction.test(shape),all=allAction.test(shape)||label(shape)==='모든명세서생성';
    if(!special&&!all)return anchor;
    let fitted=font36(shape);
    if(special){
     // Explicit paragraphs prevent a third line or a clipped Korean caption.
     const para=text=>`<a:p><a:pPr algn="ctr"><a:lnSpc><a:spcPct val="100000"/></a:lnSpc><a:spcBef><a:spcPts val="0"/></a:spcBef><a:spcAft><a:spcPts val="0"/></a:spcAft><a:defRPr sz="3600"/></a:pPr><a:r><a:rPr lang="ko-KR" sz="3600"><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:latin typeface="맑은 고딕"/><a:ea typeface="맑은 고딕"/></a:rPr><a:t>${text}</a:t></a:r><a:endParaRPr lang="ko-KR" sz="3600"/></a:p>`;
     fitted=fitted.replace(/<xdr:txBody>[\s\S]*?<\/xdr:txBody>/,`<xdr:txBody><a:bodyPr wrap="square" lIns="73152" tIns="73152" rIns="73152" bIns="73152" anchor="ctr"/><a:lstStyle/>${para('대량 및 특이')}${para('명세서 생성')}</xdr:txBody>`);
     const first=Number(anchor.match(/<xdr:from>[\s\S]*?<xdr:row>(\d+)<\/xdr:row>/)?.[1]);
     if(!Number.isFinite(first))throw Error('Missing special-button start row');
     anchor=anchor.replace(/<xdr:to>[\s\S]*?<\/xdr:to>/,to=>to.replace(/<xdr:row>(\d+)<\/xdr:row>/,(_,r)=>`<xdr:row>${Math.max(+r,first+3)}</xdr:row>`));
    }
    return anchor.replace(shape,fitted);
   });
  }else{
   next=xml.replace(/<v:shape\b[\s\S]*?<\/v:shape>/g,shape=>{
    if(!allAction.test(shape))return shape;
    return shape.replace(/<font\b[^>]*>/g,tag=>{
     // Excel VML font sizes use twentieths of a point.
     let out=tag.replace(/\bsize="[^"]*"/,'size="720"');
     if(!/\bsize="/.test(out))out=out.replace('>',' size="720">');
     return out;
    });
   });
  }
  if(next!==xml){files[path]=encode(next);changed++;}
 }
 return changed;
}

const HAS_CONTENT=`
Private Function LKInvoiceHasContent(ByVal s As Worksheet) As Boolean
    Dim nm As String, totalRow As Long, item As Range
    If Not IsError(s.Range("N2").Value2) Then nm = Trim$(CStr(s.Range("N2").Value2))
    If Len(nm) > 0 Then
        If Application.CountIf(ThisWorkbook.Worksheets(ChrW(&HBB3C) & ChrW(&HD488) & " " & ChrW(&HC785) & ChrW(&HACE0) & " " & ChrW(&HB0B4) & ChrW(&HC5ED)).Range("N6:N" & SourceLastRow), nm) > 0 Then
            LKInvoiceHasContent = True
            Exit Function
        End If
    End If
    If Not IsError(s.Range("W6").Value2) Then
        If Len(Trim$(CStr(s.Range("W6").Value2))) > 0 Then
            LKInvoiceHasContent = True
            Exit Function
        End If
    End If
    If Not IsError(s.Range("R6").Value2) Then totalRow = Val(s.Range("R6").Value2)
    If totalRow < 16 Then totalRow = 16
    For Each item In s.Range("B6:N" & totalRow - 1)
        If Not item.HasFormula And Not IsError(item.Value2) Then
            If Len(Trim$(CStr(item.Value2))) > 0 Then
                If Not IsNumeric(item.Value2) Then
                    LKInvoiceHasContent = True
                    Exit Function
                ElseIf CDbl(item.Value2) <> 0 Then
                    LKInvoiceHasContent = True
                    Exit Function
                End If
            End If
        End If
    Next item
End Function
`.replaceAll('\n','\r\n');
export function addStatementDefaultTabs(source){
 let text=binary(source);if(text.includes('LK_STATEMENT_DEFAULT_TABS_V1'))return null;
 const reset='        s.Tab.ColorIndex = xlColorIndexNone\r\n';
 const end='        If LKInvoiceIsTax(s) Then s.Tab.Color = RGB(191, 191, 191)\r\n    Next value';
 if(!text.includes(reset)||!text.includes(end))throw Error('Statement color sequence needs review');
 text=text.replace(reset,reset+"        ' LK_STATEMENT_DEFAULT_TABS_V1: data first, then delivery/tax precedence.\r\n        If LKInvoiceHasContent(s) Then\r\n            s.Tab.Color = RGB(255, 255, 0)\r\n");
 text=text.replace(end,'        If LKInvoiceIsTax(s) Then s.Tab.Color = RGB(191, 191, 191)\r\n        End If\r\n    Next value');
 return bytes(text+HAS_CONTENT);
}
