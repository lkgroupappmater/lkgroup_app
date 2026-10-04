// MS-CFB / MS-OVBA edits preserve issued numbers, formulas and row-fit procedures.
// Workbook presentation changes are limited to buttons, conditional fills and tabs.
// Format references: Microsoft [MS-CFB] and [MS-OVBA] 2.3.4 / 2.4.1.
import {enhanceStatementFeatures} from './statement-features.mjs';
import {renameStatementButtons} from './statement-button-labels.mjs';
import {addStatementTabColors} from './statement-tab-colors.mjs';
import {addSpecialStatements,addSpecialStatementButtons} from './statement-special.mjs';
import {applyTaxStatementColors} from './statement-tax-colors.mjs';
const FREE=0xffffffff,END=0xfffffffe,FAT=0xfffffffd;
const u16=(a,p)=>new DataView(a.buffer,a.byteOffset,a.byteLength).getUint16(p,true);
const u32=(a,p)=>new DataView(a.buffer,a.byteOffset,a.byteLength).getUint32(p,true);
const put32=(a,p,v)=>new DataView(a.buffer,a.byteOffset,a.byteLength).setUint32(p,v,true);
const join=parts=>{const out=new Uint8Array(parts.reduce((n,a)=>n+a.length,0));let p=0;for(const a of parts){out.set(a,p);p+=a.length;}return out;};
export function decompressVba(b){
 if(b[0]!==1)throw Error('Invalid VBA compressed container');const out=[];let p=1;
 while(p<b.length){const h=u16(b,p),end=p+(h&4095)+3,start=out.length;p+=2;if((h>>12&7)!==3||end>b.length)throw Error('Invalid VBA chunk');
  if(!(h&32768)){out.push(...b.subarray(p,end));p=end;continue;}
  while(p<end){const flags=b[p++];for(let i=0;i<8&&p<end;i++){if(flags&(1<<i)){if(p+2>end)throw Error('Truncated VBA copy');const token=u16(b,p);p+=2;const bits=Math.max(4,Math.ceil(Math.log2(out.length-start||1))),mask=65535>>>bits,distance=(token>>>(16-bits))+1,length=(token&mask)+3;if(distance>out.length-start)throw Error('Invalid VBA distance');for(let k=0;k<length;k++)out.push(out[out.length-distance]);}else out.push(b[p++]);}if(out.length-start>4096)throw Error('Oversized VBA chunk');}
 }return Uint8Array.from(out);
}
export function compressVba(bytes){
 const result=[new Uint8Array([1])];
 for(let start=0;start<bytes.length;start+=4096){const b=bytes.subarray(start,start+4096),data=[];let p=0;
  while(p<b.length){const fi=data.length;data.push(0);for(let bit=0;bit<8&&p<b.length;bit++){const bits=Math.max(4,Math.ceil(Math.log2(p||1))),maxlen=Math.min((65535>>>bits)+3,b.length-p);let best=0,distance=0;
   for(let q=p-1;q>=Math.max(0,p-(1<<bits));q--){if(b[q]!==b[p])continue;let n=1;while(n<maxlen&&b[q+n]===b[p+n])n++;if(n>best){best=n;distance=p-q;if(n===maxlen)break;}}
   if(best>=3){data[fi]|=1<<bit;const token=((distance-1)<<(16-bits))|(best-3);data.push(token&255,token>>>8);p+=best;}else data.push(b[p++]);
  }}
  if(data.length<=4096){const h=0xb000|(data.length-1);result.push(Uint8Array.from([h&255,h>>>8,...data]));}
  else{const raw=new Uint8Array(4098);raw[0]=255;raw[1]=63;raw.fill(32,2);raw.set(b,2);result.push(raw);}
 }return join(result);
}
export function readCompound(b){
 if([...b.subarray(0,8)].join(',')!=='208,207,17,224,161,177,26,225')throw Error('Invalid VBA compound document');
 const size=1<<u16(b,30),miniSize=1<<u16(b,32);if(![512,4096].includes(size)||miniSize!==64)throw Error('Unsupported VBA sector size');
 const sector=id=>{if(id>=b.length/size-1)throw Error('Invalid VBA sector');return b.subarray((id+1)*size,(id+2)*size);};
 let fatIds=[];for(let p=76;p<512;p+=4){const id=u32(b,p);if(id<0xfffffffa)fatIds.push(id);}let next=u32(b,68);const difSeen=new Set();
 while(next<0xfffffffa){if(difSeen.has(next))throw Error('Cyclic VBA DIFAT');difSeen.add(next);const data=sector(next);for(let p=0;p<size-4;p+=4){const id=u32(data,p);if(id<0xfffffffa)fatIds.push(id);}next=u32(data,size-4);}
 const fat=fatIds.flatMap(id=>{const a=sector(id);return Array.from({length:size/4},(_,p)=>u32(a,p*4));});
 const chain=(id,table,get)=>{const parts=[],seen=new Set();while(id<0xfffffffa){if(seen.has(id)||id>=table.length)throw Error('Cyclic VBA chain');seen.add(id);parts.push(get(id));id=table[id];}return join(parts);};
 const large=id=>chain(id,fat,sector),dir=large(u32(b,48)),entries=[];
 for(let p=0;p<dir.length;p+=128){const raw=dir.slice(p,p+128),len=u16(raw,64);entries.push({raw,type:raw[66],name:len?new TextDecoder('utf-16le').decode(raw.subarray(0,len-2)):'',start:u32(raw,116),size:u32(raw,120),data:null});}
 const mini=large(entries[0].start).subarray(0,entries[0].size),mf=large(u32(b,60)),miniFat=Array.from({length:mf.length/4},(_,i)=>u32(mf,i*4));
 for(const e of entries)if(e.type===2)e.data=(e.size<4096?chain(e.start,miniFat,id=>mini.subarray(id*64,id*64+64)):large(e.start)).slice(0,e.size);
 return {header:b.slice(0,size),size,entries};
}
export function writeCompound(c){
 const {size}=c,entries=c.entries.map(e=>({...e,raw:e.raw.slice()})),minis=[],miniFat=[];
 for(const e of entries)if(e.type===2&&e.data.length<4096){const count=Math.ceil(e.data.length/64);e.start=count?minis.length:END;for(let i=0;i<count;i++){const a=new Uint8Array(64);a.set(e.data.subarray(i*64,i*64+64));minis.push(a);miniFat.push(i===count-1?END:minis.length);}e.size=e.data.length;}
 const sectors=[],fat=[];
 const allocate=data=>{if(!data.length)return END;const first=sectors.length,count=Math.ceil(data.length/size);for(let i=0;i<count;i++){const a=new Uint8Array(size);a.set(data.subarray(i*size,i*size+size));sectors.push(a);fat.push(i===count-1?END:sectors.length);}return first;};
 for(const e of entries)if(e.type===2&&e.data.length>=4096){e.start=allocate(e.data);e.size=e.data.length;}
 const miniData=join(minis);entries[0].start=allocate(miniData);entries[0].size=miniData.length;
 const mf=new Uint8Array(Math.ceil(miniFat.length*4/size)*size);mf.fill(255);miniFat.forEach((v,i)=>put32(mf,i*4,v));const miniStart=allocate(mf);
 const dir=new Uint8Array(Math.ceil(entries.length*128/size)*size);entries.forEach((e,i)=>{put32(e.raw,116,e.start);put32(e.raw,120,e.size);put32(e.raw,124,0);dir.set(e.raw,i*128);});const dirStart=allocate(dir);
 let nfat=1;while(nfat*size/4<sectors.length+nfat)nfat++;if(nfat>109)throw Error('VBA project too large for bounded writer');const fatStart=sectors.length;
 for(let i=0;i<nfat;i++){sectors.push(new Uint8Array(size).fill(255));fat.push(FAT);}fat.forEach((v,i)=>put32(sectors[fatStart+Math.floor(i/(size/4))],(i%(size/4))*4,v));
 const header=c.header.slice();put32(header,40,size===4096?dir.length/size:0);put32(header,44,nfat);put32(header,48,dirStart);put32(header,60,miniStart);put32(header,64,mf.length/size);put32(header,68,END);put32(header,72,0);header.fill(255,76,512);for(let i=0;i<nfat;i++)put32(header,76+i*4,fatStart+i);
 return join([header,...sectors]);
}
const GENERATOR=`Public Sub CreateInvoiceSheets02To100()
    ' LK_CURRENT_VOYAGE_STATEMENTS_V2 - keep the old entry point for existing buttons.
    CreateCurrentVoyageInvoiceSheets
End Sub

Public Sub CreateCurrentVoyageInvoiceSheets()
    Dim customers As Worksheet, template As Worksheet, anchor As Worksheet
    Dim s As Worksheet, originalSheet As Object, bills As Collection
    Dim header As Range, r As Long, lastRow As Long, billCol As Long, headerRow As Long
    Dim nm As String, suffix As String, customerName As String, value As Variant, badChar As Variant
    Dim priorEvents As Boolean, priorScreen As Boolean, failText As String
    Set originalSheet = ActiveSheet
    priorEvents = Application.EnableEvents
    priorScreen = Application.ScreenUpdating
    On Error GoTo Failed
    Application.EnableEvents = False
    Application.ScreenUpdating = False
    LKEnsureUngrouped
    Application.Calculate
    Set customers = ThisWorkbook.Worksheets(ChrW(&HACE0) & ChrW(&HAC1D) & " " & ChrW(&HB9AC) & ChrW(&HC2A4) & ChrW(&HD2B8))
    For Each header In customers.Range("A1:Z20")
        If Not IsError(header.Value2) Then
            If LCase$(Replace(Replace(Replace(Trim$(CStr(header.Value2)), ".", ""), " ", ""), vbLf, "")) = "nobill" Then
                billCol = header.Column
                headerRow = header.Row
                Exit For
            End If
        End If
    Next header
    If billCol = 0 Then Err.Raise vbObjectError + 514, , "No. Bill header was not found."
    lastRow = customers.Cells(customers.Rows.Count, billCol).End(xlUp).Row
    Set bills = New Collection
    ' Validate the complete list before creating any sheets; retain list order.
    For r = headerRow + 1 To lastRow
        If IsError(customers.Cells(r, billCol).Value2) Or IsError(customers.Cells(r, billCol + 1).Value2) Then
            Err.Raise vbObjectError + 515, , "Check the customer list, row " & r
        End If
        nm = Trim$(CStr(customers.Cells(r, billCol).Value2))
        customerName = Trim$(CStr(customers.Cells(r, billCol + 1).Value2))
        If Len(nm) > 0 And Len(customerName) > 0 And StrComp(Left$(nm, Len(Trim$(InvoicePrefix))), Trim$(InvoicePrefix), vbTextCompare) = 0 Then
            suffix = Trim$(Mid$(nm, Len(Trim$(InvoicePrefix)) + 1))
            If Len(suffix) = 0 Or Len(nm) > 31 Then Err.Raise vbObjectError + 516, , "Check No. Bill at row " & r & ": [" & nm & "]"
            ' Preserve the actual issued number, including valid manual suffixes.
            For Each badChar In Array(":", ChrW(92), "/", "?", "*", "[", "]")
                If InStr(nm, CStr(badChar)) > 0 Then Err.Raise vbObjectError + 516, , "No. Bill contains an invalid sheet-name character at row " & r & ": [" & nm & "]"
            Next badChar
            On Error Resume Next
            bills.Add nm, LCase$(nm)
            Err.Clear
            On Error GoTo Failed
        End If
    Next r
    If bills.Count = 0 Then GoTo CleanUp
    On Error Resume Next
    Set template = ThisWorkbook.Worksheets(InvoicePrefix & "01")
    If template Is Nothing Then Set template = ThisWorkbook.Worksheets(ChrW(&HBA85) & ChrW(&HC138) & ChrW(&HC11C) & " " & ChrW(&HBE60) & ChrW(&HB974) & ChrW(&HAC8C) & " " & ChrW(&HD655) & ChrW(&HC778))
    Set anchor = ThisWorkbook.Worksheets(InvoicePrefix & "XX")
    On Error GoTo Failed
    If template Is Nothing Then
        For Each s In ThisWorkbook.Worksheets
            If IsInvoiceSheet(s) Then
                Set template = s
                Exit For
            End If
        Next s
    End If
    If template Is Nothing Then Err.Raise vbObjectError + 517, , "An invoice template was not found."
    For Each value In bills
        nm = CStr(value)
        Set s = Nothing
        On Error Resume Next
        Set s = ThisWorkbook.Worksheets(nm)
        On Error GoTo Failed
        If s Is Nothing Then
            If anchor Is Nothing Then
                template.Copy After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count)
            Else
                template.Copy Before:=anchor
            End If
            Set s = ActiveSheet
            s.Name = nm
            s.Range("N2").Value = nm
        End If
        FitOne s
    Next value
CleanUp:
    If Not originalSheet Is Nothing Then originalSheet.Activate
    Application.EnableEvents = priorEvents
    Application.ScreenUpdating = priorScreen
    If Len(failText) > 0 Then MsgBox failText, vbExclamation
    Exit Sub
Failed:
    failText = Err.Description
    Resume CleanUp
End Sub
`.replaceAll('\n','\r\n');
const GROUP_GUARD = `    ' LK_GROUPED_SHEET_GUARD_V1: do not mutate/recalculate grouped tabs.
    If Application.ActiveWindow Is Nothing Then Exit Sub
    If Not (Application.ActiveWorkbook Is ThisWorkbook) Then Exit Sub
    If Application.ActiveWindow.SelectedSheets.Count > 1 Then Exit Sub
`.replaceAll('\n','\r\n');
const ascii=new TextEncoder();
function indexOfBytes(bytes,needle,start=0){outer:for(let i=start;i<=bytes.length-needle.length;i++){for(let j=0;j<needle.length;j++)if(bytes[i+j]!==needle[j])continue outer;return i;}return -1;}
export function upgradeStatementMacros(files){
 const original=files['xl/vbaProject.bin'];if(!original)return {present:false,changed:false};
 const c=readCompound(original),marker=ascii.encode('LK_CURRENT_VOYAGE_STATEMENTS_V2'),entry=ascii.encode('Public Sub CreateInvoiceSheets02To100()'),end=ascii.encode('End Sub');let changed=0,present=false,dirChanged=false,groupGuard=false,unsafeGroupRefresh=false;const eventSources=[];
 const dirEntry=c.entries.find(e=>e.name==='dir'),dir=dirEntry?decompressVba(dirEntry.data):null;
 for(const e of c.entries){if(e.type!==2||['dir','_VBA_PROJECT','PROJECT','PROJECTwm'].includes(e.name)||e.name.startsWith('__SRP_'))continue;
  let src,offsetRecord=-1,offset=0;
  if(dir){const name=ascii.encode(e.name),prefix=new Uint8Array(6);prefix[0]=25;put32(prefix,2,name.length);const moduleStart=indexOfBytes(dir,join([prefix,name]));if(moduleStart>=0){const termination=indexOfBytes(dir,new Uint8Array([43,0,0,0,0,0]),moduleStart),found=indexOfBytes(dir,new Uint8Array([49,0,4,0,0,0]),moduleStart);if(found>=0&&(termination<0||found<termination)){offsetRecord=found+6;offset=u32(dir,offsetRecord);}}}
  try{src=decompressVba(e.data.subarray(offset));}catch{continue;}
  const enhanced=enhanceStatementFeatures(src,e.name);
  if(enhanced){src=enhanced;e.data=compressVba(src);if(offset){if(offsetRecord<0)throw Error('Missing feature module offset');put32(dir,offsetRecord,0);dirChanged=true;}changed++;}
  if(/Workbook_(SheetActivate|SheetChange|Open)/.test(new TextDecoder().decode(src)))eventSources.push({module:e.name,source:new TextDecoder('euc-kr').decode(src)});
  if(e.name==='ThisWorkbook'){
   const refresh=ascii.encode('Private Sub RefreshInvoice(ByVal Sh As Object)\r\n    On Error GoTo Failed\r\n');
   const at=indexOfBytes(src,refresh),guardMarker=ascii.encode('LK_GROUPED_SHEET_GUARD_V1');
   if(indexOfBytes(src,guardMarker)>=0)groupGuard=true;
   else if(at>=0&&indexOfBytes(src,ascii.encode('If IsInvoiceSheet(Sh) Then FitOne Sh'),at)>=0){
    unsafeGroupRefresh=true;groupGuard=true;
    src=join([src.subarray(0,at+refresh.length),ascii.encode(GROUP_GUARD),src.subarray(at+refresh.length)]);
    e.data=compressVba(src);
    if(offset){if(offsetRecord<0)throw Error('Missing workbook module offset');put32(dir,offsetRecord,0);dirChanged=true;}
    changed++;
   } else if(indexOfBytes(src,ascii.encode('RefreshKrwAccount Sh'))>=0){
    let eventsPatched=0;
    for(const event of ['Workbook_SheetActivate','Workbook_SheetCalculate']){
     const signature=ascii.encode('Private Sub '+event+'(ByVal Sh As Object)\r\n'),eventAt=indexOfBytes(src,signature);
     if(eventAt>=0){src=join([src.subarray(0,eventAt+signature.length),ascii.encode(GROUP_GUARD),src.subarray(eventAt+signature.length)]);eventsPatched++;}
    }
    if(eventsPatched){
     unsafeGroupRefresh=true;groupGuard=true;e.data=compressVba(src);
     if(offset){if(offsetRecord<0)throw Error('Missing workbook module offset');put32(dir,offsetRecord,0);dirChanged=true;}
     changed++;
    }
   }
  }
  if(indexOfBytes(src,marker)>=0){
   present=true;const tabbed=addStatementTabColors(src),special=addSpecialStatements(tabbed||src);
   if(tabbed||special){e.data=compressVba(special||tabbed);if(offset){if(offsetRecord<0)throw Error('Missing delivery-tab module offset');put32(dir,offsetRecord,0);dirChanged=true;}changed++;}
   continue;
  }
  const start=indexOfBytes(src,entry);if(start<0)continue;present=true;let finish=indexOfBytes(src,end,start);if(finish<0)throw Error('Invoice generator is incomplete');
  const old=new TextDecoder('windows-1252').decode(src.subarray(start,finish));
  if(old.includes('LK_CURRENT_VOYAGE_STATEMENTS_V1')){const next=indexOfBytes(src,ascii.encode('Public Sub CreateCurrentVoyageInvoiceSheets()'),finish);if(next<0)throw Error('Current-voyage generator is incomplete');finish=indexOfBytes(src,end,next);if(finish<0)throw Error('Current-voyage generator is incomplete');}
  else if(!/For i = 2 To 100\b/.test(old))throw Error('Invoice generator has another revision; review before updating');
  const generated=join([src.subarray(0,start),ascii.encode(GENERATOR),src.subarray(finish+end.length)]),tabbed=addStatementTabColors(generated)||generated,next=addSpecialStatements(tabbed)||tabbed;e.data=compressVba(next);const roundtrip=decompressVba(e.data);if(indexOfBytes(roundtrip,marker)<0)throw Error('VBA roundtrip failed');if(offset){if(offsetRecord<0)throw Error('Missing VBA module offset');put32(dir,offsetRecord,0);dirChanged=true;}changed++;
 }
 if(!present){if(Object.entries(files).some(([p,b])=>/\.(xml|vml)$/.test(p)&&/CreateInvoiceSheets02To100/.test(new TextDecoder().decode(b))))throw Error('Invoice macro source needs review');return {present:false,changed:false};}
 if(changed){if(dirChanged)dirEntry.data=compressVba(dir);const cache=c.entries.find(e=>e.name==='_VBA_PROJECT');if(cache)cache.data=new Uint8Array([0xcc,0x61,0xff,0xff,0,3,0]);for(const e of c.entries)if(e.name.startsWith('__SRP_'))e.data=new Uint8Array();files['xl/vbaProject.bin']=writeCompound(c);}
 const {buttons}=renameStatementButtons(files);
 const specialButtons=addSpecialStatementButtons(files),taxColors=applyTaxStatementColors(files);
 return {present:true,changed:!!(changed||buttons||specialButtons||taxColors),modules:changed,buttons,special_buttons:specialButtons,tax_color_parts:taxColors,grouped_sheet_guard:groupGuard,unguarded_group_refresh_found:unsafeGroupRefresh,workbook_events:eventSources,version:'all-special-statements-gray-v5'};
}
