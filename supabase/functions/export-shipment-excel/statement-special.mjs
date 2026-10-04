// One additional user-facing macro; both buttons use the existing generator.
const binary=b=>Array.from(b,c=>String.fromCharCode(c)).join('');
const bytes=s=>Uint8Array.from(s,c=>c.charCodeAt(0));
const vb=s=>[...s].map(c=>c.charCodeAt(0)>127?`ChrW(&H${c.charCodeAt(0).toString(16).toUpperCase()})`:`"${c.replaceAll('"','""')}"`).join(' & ');
const routineWords=['지상사협의회회원사','법인장지인','아파트고객','기업','특별','한국','카카오톡','카톡','명세서','선공유','온라인','결재','결제','및','일반','라선협','회원','대표','고정','기부','할인율','할인','적용'];
// Remove only routine words and percentage syntax. Residual instructions still qualify.
export function hasSpecialRemark(value){
 let s=String(value??'').replace(/\s/g,'');
 if(s&&!routineWords.some(word=>s.includes(word))&&!s.includes('%'))return true;
 for(const word of routineWords)s=s.replaceAll(word,'');
 return s.replace(/[0-9.%/;,|()\[\]:+-]/g,'').length>0;
}
const HELPERS=`
' LK_SPECIAL_STATEMENTS_V2
Private Function LKCompact(ByVal value As Variant) As String
    If IsError(value) Then
        LKCompact = "#ERROR"
        Exit Function
    End If
    LKCompact = Replace(Replace(Replace(Replace(Replace(CStr(value), " ", ""), vbTab, ""), vbCr, ""), vbLf, ""), ChrW(160), "")
End Function

Private Function LKHasSpecialRemark(ByVal value As Variant) As Boolean
    Dim t As String, original As String, item As Variant, i As Long
    t = LKCompact(value)
    original = t
${routineWords.map(w=>`    t = Replace(t, ${vb(w)}, "")`).join('\n')}
    If t = original And Len(t) > 0 And InStr(t, "%") = 0 Then
        LKHasSpecialRemark = True
        Exit Function
    End If
    For i = 0 To 9
        t = Replace(t, CStr(i), "")
    Next i
    For Each item In Array(".", "%", "/", ";", ",", "|", "(", ")", "[", "]", ":", "+", "-")
        t = Replace(t, CStr(item), "")
    Next item
    LKHasSpecialRemark = Len(t) > 0
End Function

Private Function LKTaxText(ByVal value As Variant) As Boolean
    LKTaxText = InStr(LKCompact(value), ${vb('세금계산서')}) > 0 Or InStr(LKCompact(value), ${vb('영세율')}) > 0
End Function

Private Function LKInvoiceIsTax(ByVal s As Worksheet) As Boolean
    Dim totalRow As Long, cargo As Worksheet, r As Long, nm As String
    If Not IsError(s.Range("R6").Value2) Then
        totalRow = Val(s.Range("R6").Value2)
        If totalRow >= 16 Then
            If LKTaxText(s.Cells(totalRow + 2, 1).Value2) Then
                LKInvoiceIsTax = True
                Exit Function
            End If
        End If
    End If
    nm = Trim$(CStr(s.Range("N2").Value2))
    If Len(nm) = 0 Then Exit Function
    Set cargo = ThisWorkbook.Worksheets(${vb('물품 입고 내역')})
    For r = 6 To SourceLastRow
        If Not IsError(cargo.Cells(r, 14).Value2) Then
            If StrComp(Trim$(CStr(cargo.Cells(r, 14).Value2)), nm, vbTextCompare) = 0 Then
                If LKTaxText(cargo.Cells(r, 16).Value2) Then
                    LKInvoiceIsTax = True
                    Exit Function
                End If
            End If
        End If
    Next r
End Function

Private Function LKNeedsSpecialStatement(ByVal nm As String) As Boolean
    Dim cargo As Worksheet, fees As Worksheet, s As Worksheet
    Dim r As Long, n As Long, extra As Long, last As Long, col As Variant
    Dim special As Boolean, totalRow As Long, account As String
    Set cargo = ThisWorkbook.Worksheets(${vb('물품 입고 내역')})
    For r = 6 To SourceLastRow
        If Not IsError(cargo.Cells(r, 14).Value2) Then
            If StrComp(Trim$(CStr(cargo.Cells(r, 14).Value2)), nm, vbTextCompare) = 0 Then
                n = n + 1
                For Each col In Array(16, 18, 19, 20)
                    If LKHasSpecialRemark(cargo.Cells(r, CLng(col)).Value2) Then special = True
                Next col
            End If
        End If
    Next r
    If n = 0 Then Exit Function
    On Error Resume Next
    Set fees = ThisWorkbook.Worksheets(${vb('기타 비용 추가 입력')})
    Set s = ThisWorkbook.Worksheets(nm)
    On Error GoTo 0
    If Not fees Is Nothing Then
        last = fees.Cells(fees.Rows.Count, 1).End(xlUp).Row
        For r = 5 To last
            If Not IsError(fees.Cells(r, 1).Value2) Then
                If StrComp(Trim$(CStr(fees.Cells(r, 1).Value2)), nm, vbTextCompare) = 0 Then
                    If Len(LKCompact(fees.Cells(r, 3).Value2)) > 0 Then
                        extra = extra + 1
                        special = True
                    End If
                End If
            End If
        Next r
    End If
    If Not s Is Nothing Then
        If Not IsError(s.Range("W12").Value2) Then
            If Val(s.Range("W12").Value2) > extra Then extra = Val(s.Range("W12").Value2)
        End If
        If Not IsError(s.Range("R6").Value2) Then
            totalRow = Val(s.Range("R6").Value2)
            If totalRow >= 16 Then
                If LKHasSpecialRemark(s.Cells(totalRow + 2, 1).Value2) Then special = True
            End If
        End If
        account = LKCompact(s.Range("W14").Value2)
        If Len(account) > 0 Then
            If account <> ${vb('한국원화계좌:경남은행571-22-0330221박성호')} Then special = True
        End If
    End If
    LKNeedsSpecialStatement = special Or n + extra + 1 >= 11
End Function
`;
export function addSpecialStatements(source){
 let text=binary(source);
 if(text.includes('LK_SPECIAL_STATEMENTS_V2'))return null;
 if(text.includes('LK_SPECIAL_STATEMENTS_V1')){
  const pattern=/Private Function LKHasSpecialRemark\b[\s\S]*?End Function/;
  if(!pattern.test(text))throw Error('Special remark filter needs review');
  return bytes(text.replace(pattern,HELPERS.match(pattern)[0].replaceAll('\n','\r\n')).replace('LK_SPECIAL_STATEMENTS_V1','LK_SPECIAL_STATEMENTS_V2'));
 }
 const signature='Public Sub CreateCurrentVoyageInvoiceSheets()\r\n';
 if(!text.includes(signature))return null;
 text=text.replace(signature,`Public Sub CreateCurrentVoyageInvoiceSheets()
    LKCreateInvoiceSheets False
End Sub

Public Sub CreateBulkSpecialInvoiceSheets()
    LKCreateInvoiceSheets True
End Sub

Private Sub LKCreateInvoiceSheets(ByVal onlySpecial As Boolean)
`.replaceAll('\n','\r\n'));
 const anchor='            On Error Resume Next\r\n            bills.Add nm, LCase$(nm)\r\n            Err.Clear\r\n            On Error GoTo Failed';
 if(!text.includes(anchor))throw Error('Review generator before adding the special filter');
 text=text.replace(anchor,'            If Not onlySpecial Or LKNeedsSpecialStatement(nm) Then\r\n'+anchor+'\r\n            End If');
 // Gray takes precedence over delivery colors, including zero-rated invoices.
 const endColor='        Next r\r\n    Next value';
 if(!text.includes(endColor))throw Error('Missing statement tab-color integration');
 text=text.replace(endColor,'        Next r\r\n        If LKInvoiceIsTax(s) Then s.Tab.Color = RGB(191, 191, 191)\r\n    Next value');
 return bytes(text+HELPERS.replaceAll('\n','\r\n'));
}

export function addSpecialStatementButtons(files){
 let count=0;
 for(const [path,data] of Object.entries(files)){
  if(!/^xl\/drawings\/drawing[^/]*\.xml$/.test(path))continue;
  const xml=new TextDecoder().decode(data);
  if(xml.includes('CreateBulkSpecialInvoiceSheets'))continue;
  const anchor=[...xml.matchAll(/<xdr:twoCellAnchor\b[\s\S]*?<\/xdr:twoCellAnchor>/g)].map(m=>m[0]).find(a=>a.includes('모든 명세서 생성'));
  if(!anchor)continue;
  const id=1+Math.max(0,...[...xml.matchAll(/<xdr:cNvPr\b[^>]*\bid="(\d+)"/g)].map(m=>+m[1]));
  let copy=anchor.replace(/<xdr:twoCellAnchor\b[^>]*>/,'<xdr:twoCellAnchor editAs="absolute">').replace(/<xdr:row>(\d+)<\/xdr:row>/g,(_,r)=>`<xdr:row>${+r+3}</xdr:row>`)
   .replace(/<xdr:sp\b[^>]*>/,'<xdr:sp macro="[0]!CreateBulkSpecialInvoiceSheets" textlink="">')
   .replace(/<xdr:cNvPr\b[\s\S]*?<\/xdr:cNvPr>/,`<xdr:cNvPr id="${id}" name="LK Bulk Special Statements"/>`)
   .replace(/\bsz="\d+"/g,'sz="2800"')
   .replace('<a:noFill/>','<a:solidFill><a:srgbClr val="E7E6E6"/></a:solidFill>')
   .replaceAll('모든 명세서 생성','대량 및 특이 명세서 생성');
  // A normal DrawingML shape has its own macro action, with no legacy control IDs.
  if(copy.includes('compatExt')||copy.includes('hidden="1"'))throw Error('Special button retains hidden control metadata');
  files[path]=new TextEncoder().encode(xml.replace('</xdr:wsDr>',copy+'</xdr:wsDr>'));count++;
 }
 return count;
}
