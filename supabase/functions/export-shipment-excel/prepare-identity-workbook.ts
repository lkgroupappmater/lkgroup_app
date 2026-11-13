import {strFromU8,strToU8,Unzip} from 'npm:fflate@0.8.2';
import {applyCustomerIdWorkbook} from './customer-id-workbook.mjs';
import {formatDeliveryNumbers} from './delivery-number-format.mjs';
import {restoreSharedFormulaMasters,captureSharedFormulaMasters} from './workbook-integrity.mjs';
import {copySharedDeliveryLayout,deliverySheetIndex} from './shared-delivery-layout.mjs';
import {unzipWorkbook} from './workbook-zip.mjs';

// This internal context travels only between authenticated server requests.
// It is removed before the finished workbook is ever stored or downloaded.
export const IDENTITY_CONTEXT_ENTRY='_lk_internal_identity_context.json';
export async function prepareIdentityWorkbook(files:Record<string,Uint8Array>,routeKey:string,downloadDeliveryLayout?:(path:string)=>Promise<Uint8Array>){
 const bytes=files[IDENTITY_CONTEXT_ENTRY];
 if(!bytes)throw new Error('Excel identity context is missing.');
 const data=JSON.parse(strFromU8(bytes));delete files[IDENTITY_CONTEXT_ENTRY];
 if(data.version!==1||data.routeKey!==routeKey||!Array.isArray(data.identityContext?.customers)||!Array.isArray(data.enrichedShipments)||!Array.isArray(data.sharedMasters))throw new Error('Invalid Excel identity context.');
 const {identityContext,enrichedShipments,isBaseRefresh,receiptPrefix}=data;
 const originalSharedMasters=new Map(data.sharedMasters.map(([path,masters]:[string,Array<[string,unknown]>])=>[path,new Map(masters)]));
 let deliveryLayout=null;
 if(data.deliveryLayoutSource){
  const layout=data.deliveryLayoutSource;
  if(!['kr_la_sea','kr_la_air'].includes(routeKey)||!['kr_la_sea','kr_la_air'].includes(layout.route_key)||typeof layout.storage_path!=='string'||
     ![`base/${layout.route_key}/`,`macro-updates/${layout.route_key}/`].some(p=>layout.storage_path.startsWith(p))||!downloadDeliveryLayout)throw Error('Invalid common delivery layout context');
  // Read the immutable source inside the existing authenticated processing stage.
  // Do not embed a nested ZIP in the streamed workbook passed between stages.
  const layoutBytes=await downloadDeliveryLayout(layout.storage_path);
  const meta=await unzipWorkbook(layoutBytes,{Unzip,filter:(entry:any)=>['xl/workbook.xml','xl/_rels/workbook.xml.rels'].includes(entry.name)});
  const paths=deliverySheetIndex(meta).filter((s:any)=>['지방배송','시내배송'].includes(s.name)).map((s:any)=>s.path);
  const source=await unzipWorkbook(layoutBytes,{Unzip,filter:(entry:any)=>!entry.name.startsWith('xl/worksheets/')||paths.includes(entry.name)||paths.some((p:string)=>entry.name===p.replace('/worksheets/','/worksheets/_rels/')+'.rels')});
  const sheets=copySharedDeliveryLayout(files,source);
  const updatedMasters=captureSharedFormulaMasters(files);
  for(const sheet of sheets)originalSharedMasters.set(sheet.target_path,updatedMasters.get(sheet.target_path)||new Map());
  deliveryLayout={version:1,source:data.deliveryLayoutSource,sheets};
 }
    applyCustomerIdWorkbook(files,identityContext,{prefix:receiptPrefix,shipments:enrichedShipments,base:isBaseRefresh,preserveSharedMasters:false,managedDelivery:['kr_la_sea','kr_la_air'].includes(routeKey),preserveDeliveryLayout:!!deliveryLayout});
    // BASE refreshes and voyage exports must both repair inherited presentation.
    // Run after delivery input updates so newly filled number cells are covered.
    formatDeliveryNumbers(files, routeKey);
    // Patch133: Row data 하단 SYSTEM SETTLEMENT 중복 블록은 더 이상 추가하지 않습니다.
// 수식 셀 자체는 보존하고, 오래된 calcChain만 정상적으로 제거합니다.
    // calcChain을 파일만 지우고 관계/ContentType을 남기면 Excel이 복구 경고를 낼 수 있습니다.
    delete files['xl/calcChain.xml'];

    const relsPath = 'xl/_rels/workbook.xml.rels';
    if (files[relsPath]) {
      let relsXml = strFromU8(files[relsPath]);
      relsXml = relsXml.replace(
        /<Relationship\b[^>]*Type="http:\/\/schemas\.openxmlformats\.org\/officeDocument\/2006\/relationships\/calcChain"[^>]*\/>/g,
        '',
      );
      files[relsPath] = strToU8(relsXml);
    }

    const contentTypesPath = '[Content_Types].xml';
    if (files[contentTypesPath]) {
      let contentTypesXml = strFromU8(files[contentTypesPath]);
      contentTypesXml = contentTypesXml.replace(
        /<Override\b[^>]*PartName="\/xl\/calcChain\.xml"[^>]*\/>/g,
        '',
      );
      files[contentTypesPath] = strToU8(contentTypesXml);
    }

    // Excel에서 기존 VLOOKUP/INDEX/MATCH 수식을 다시 계산하도록 지정합니다.
    let workbookXml = strFromU8(files['xl/workbook.xml']);
    if (/<calcPr\b/.test(workbookXml)) {
      workbookXml = workbookXml.replace(
        /<calcPr\b[^>]*\/>/,
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>',
      );
    } else {
      workbookXml = workbookXml.replace(
        '</workbook>',
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>',
      );
    }
    files['xl/workbook.xml'] = strToU8(workbookXml);

    // Native DEFLATE retains normal XLSM size without spending Edge CPU on a
    // JavaScript compressor. VBA and all other parts remain byte-identical.
    restoreSharedFormulaMasters(files,originalSharedMasters);
 return deliveryLayout;
}

