// Add account refresh and grouped-tab isolation without re-encoding Korean VBA.
const binary=bytes=>Array.from(bytes,b=>String.fromCharCode(b)).join('');
const bytes=text=>Uint8Array.from(text,c=>c.charCodeAt(0));
const crlf=text=>text.replace(/\r?\n/g,'\r\n');
const vbText=text=>[...text].map(c=>c.charCodeAt(0)>127?`ChrW(&H${c.charCodeAt(0).toString(16).toUpperCase()})`:`"${c.replaceAll('"','""')}"`).join(' & ');
// Same account rule and numbers already present in the approved BASEs.
const accountFormula='"한국 원화 계좌:"&CHAR(10)&"경남은행"&CHAR(10)&IF(ISNUMBER(SEARCH("세금계산서",SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE({TAX}," ",""),CHAR(9),""),CHAR(10),""),CHAR(13),""),CHAR(160),""))),"2070133424601"&CHAR(10)&"박성호(엘케이무역)","571-22-0330221"&CHAR(10)&"박성호")';
const formulaBuilder=[...accountFormula].reduce((a,c,i)=>{if(i%35===0)a.push('');a[a.length-1]+=c;return a;},[]).map(s=>'    t = t & '+vbText(s)).join('\n');
const HELPERS=crlf(`
' LK_STATEMENT_FEATURES_V2
Public Sub LKEnsureUngrouped()
    If Application.ActiveWorkbook Is ThisWorkbook Then
        If Not Application.ActiveWindow Is Nothing Then
            If Application.ActiveWindow.SelectedSheets.Count > 1 Then ThisWorkbook.ActiveSheet.Select
        End If
    End If
End Sub

Private Function LKDefaultAccountFormula() As String
    Dim t As String
${formulaBuilder}
    LKDefaultAccountFormula = "=" & t
End Function

Public Sub LKRefreshInvoiceAccount(ByVal s As Worksheet)
    Static busy As Boolean
    Dim box As Shape, expected As String, existing As String, link As String
    Dim totalRow As Long, fontName As String, fontColor As Long
    Dim failNumber As Long, failText As String
    If busy Or Not IsInvoiceSheet(s) Then Exit Sub
    If Application.ActiveWorkbook Is ThisWorkbook Then
        If Not Application.ActiveWindow Is Nothing Then
            If Application.ActiveWindow.SelectedSheets.Count > 1 Then Exit Sub
        End If
    End If
    busy = True
    On Error GoTo Failed
    If Len(s.Range("W14").Formula) = 0 Then
        totalRow = CLng(s.Range("R6").Value2)
        If totalRow < 16 Then Err.Raise vbObjectError + 518, , "Check invoice total row."
        s.Range("W14").Formula = Replace(LKDefaultAccountFormula(), "{TAX}", s.Cells(totalRow + 2, 1).Address)
    End If
    s.Calculate
    If IsError(s.Range("W14").Value2) Then Err.Raise vbObjectError + 519, , "Check the KRW account formula in W14."
    expected = CStr(s.Range("W14").Value2)
    If InStr(expected, "2070133424601") = 0 And InStr(expected, "571-22-0330221") = 0 Then GoTo CleanUp
    For Each box In s.Shapes
        If box.Type = msoTextBox Then
            existing = box.TextFrame.Characters.Text
            If InStr(existing, "2070133424601") > 0 Or InStr(existing, "571-22-0330221") > 0 Then
                fontName = box.TextFrame.Characters(1, 1).Font.Name
                fontColor = box.TextFrame.Characters(1, 1).Font.Color
                link = "='" & Replace(s.Name, "'", "''") & "'!$W$14"
                If Replace(Replace(existing, vbCrLf, vbLf), vbCr, vbLf) <> expected Or box.DrawingObject.Formula <> link Then
                    box.DrawingObject.Formula = ""
                    box.DrawingObject.Formula = link
                End If
                With box.TextFrame.Characters.Font
                    .Name = fontName
                    .Size = 44
                    .Bold = True
                    .Color = fontColor
                End With
                box.TextFrame.HorizontalAlignment = xlHAlignCenter
                box.TextFrame.VerticalAlignment = xlVAlignCenter
            End If
        End If
    Next box
CleanUp:
    busy = False
    If failNumber <> 0 Then Err.Raise failNumber, "LKRefreshInvoiceAccount", failText
    Exit Sub
Failed:
    failNumber = Err.Number
    failText = Err.Description
    Resume CleanUp
End Sub

Public Sub LKRefreshAllInvoiceAccounts()
    Dim s As Worksheet
    For Each s In ThisWorkbook.Worksheets
        If IsInvoiceSheet(s) Then LKRefreshInvoiceAccount s
    Next s
End Sub

Public Sub LKInvoiceChanged(ByVal Sh As Object, ByVal Target As Range)
    Dim taxRow As Long
    If Not TypeOf Sh Is Worksheet Then Exit Sub
    If Not IsInvoiceSheet(Sh) Then Exit Sub
    If IsError(Sh.Range("R6").Value2) Then Exit Sub
    taxRow = CLng(Sh.Range("R6").Value2) + 2
    If taxRow < 18 Then Exit Sub
    If Intersect(Target, Union(Sh.Range("N2"), Sh.Cells(taxRow, 1))) Is Nothing Then Exit Sub
    LKRefreshInvoiceAccount Sh
End Sub
`);

export function enhanceStatementFeatures(source,moduleName){
 let text=binary(source),next=text;
 if(moduleName==='ThisWorkbook'){
  if(text.includes('LK_STATEMENT_EVENTS_V2'))return null;
  const events=[
   ['Workbook_Open','()', 'LKRefreshAllInvoiceAccounts'],
   ['Workbook_BeforeSave','(ByVal SaveAsUI As Boolean, Cancel As Boolean)', 'LKRefreshAllInvoiceAccounts'],
   ['Workbook_BeforePrint','(Cancel As Boolean)', 'LKRefreshAllInvoiceAccounts'],
   ['Workbook_SheetCalculate','(ByVal Sh As Object)', 'If TypeOf Sh Is Worksheet Then LKRefreshInvoiceAccount Sh'],
   ['Workbook_SheetActivate','(ByVal Sh As Object)', 'If TypeOf Sh Is Worksheet Then LKRefreshInvoiceAccount Sh'],
   ['Workbook_SheetChange','(ByVal Sh As Object, ByVal Target As Range)', 'LKInvoiceChanged Sh, Target'],
  ];
  for(const [name,args,call] of events){
   const signature=new RegExp('(Private Sub '+name+'\\([^\\r\\n]*\\)\\r?\\n)');
   if(signature.test(next))next=next.replace(signature,'$1    '+call+'\r\n');
   else next+=crlf(`\nPrivate Sub ${name}${args}\n    ${call}\nEnd Sub\n`);
  }
  next+="\r\n' LK_STATEMENT_EVENTS_V2\r\n";
 }else if(/Public Sub CreateInvoiceSheets02To100\(\)/.test(text)){
  if(text.includes('LK_STATEMENT_FEATURES_V2'))return null;
  next=next.replace(/Public Sub (FitOne|RestoreHeaderFontSizes)\b[\s\S]*?End Sub/g,procedure=>{
   let result=procedure.replace('    Application.ScreenUpdating = False\r\n','    Application.ScreenUpdating = False\r\n    LKEnsureUngrouped\r\n');
   if(procedure.startsWith('Public Sub FitOne')){
    result=result.replace('    RefreshKrwAccount s\r\n','');
    result=result.replace('    s.Calculate\r\n','    s.Calculate\r\n    LKRefreshInvoiceAccount s\r\n');
   }
   return result;
  });
  next+=HELPERS;
 }
 return next===text?null:bytes(next);
}
