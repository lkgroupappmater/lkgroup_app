// Extend the existing generator inline. No new VBA macro or button is added.
const binary=bytes=>Array.from(bytes,b=>String.fromCharCode(b)).join('');
const bytes=text=>Uint8Array.from(text,c=>c.charCodeAt(0));
const crlf=text=>text.replace(/\r?\n/g,'\r\n');
const block=crlf(`        ' LK_DELIVERY_TAB_COLORS_V1: copy the customer list's displayed fill.
        s.Tab.ColorIndex = xlColorIndexNone
        For r = headerRow + 1 To lastRow
            If Not IsError(customers.Cells(r, billCol).Value2) Then
                If StrComp(Trim$(CStr(customers.Cells(r, billCol).Value2)), nm, vbTextCompare) = 0 Then
                    Set deliveryCell = customers.Cells(r, billCol + 4)
                    If Not IsError(deliveryCell.Value2) Then
                        deliveryText = Replace(CStr(deliveryCell.Value2), " ", "")
                        If InStr(deliveryText, ChrW(&HC9C0) & ChrW(&HBC29) & ChrW(&HBC30) & ChrW(&HC1A1)) > 0 Or InStr(deliveryText, ChrW(&HC2DC) & ChrW(&HB0B4) & ChrW(&HBC30) & ChrW(&HC1A1)) > 0 Then
                            s.Tab.Color = deliveryCell.DisplayFormat.Interior.Color
                        End If
                    End If
                    Exit For
                End If
            End If
        Next r
`);
export function addStatementTabColors(source) {
  const text=binary(source);
  if(text.includes('LK_DELIVERY_TAB_COLORS_V1'))return null;
  const signature='Public Sub CreateCurrentVoyageInvoiceSheets()\r\n';
  const start=text.indexOf(signature);if(start<0)return null;
  const end=text.indexOf('End Sub',start);if(end<0)throw Error('Invoice generator is incomplete');
  const procedure=text.slice(start,end),anchor='        FitOne s\r\n    Next value';
  if(!procedure.includes(anchor))throw Error('Invoice generator needs review before adding delivery tab colors');
  const next=procedure.replace(signature,signature+'    Dim deliveryCell As Range, deliveryText As String\r\n').replace(anchor,'        FitOne s\r\n'+block+'    Next value');
  return bytes(text.slice(0,start)+next+text.slice(end));
}
