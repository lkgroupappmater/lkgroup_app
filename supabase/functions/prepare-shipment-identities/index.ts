import {Unzip,Zip,ZipPassThrough} from 'npm:fflate@0.8.2';
import {createWorkbookIdentityHandler} from '../export-shipment-excel/workbook-identity-handler.mjs';
import {prepareIdentityWorkbook} from '../export-shipment-excel/prepare-identity-workbook.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';

const url=Deno.env.get('SUPABASE_URL')!,serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
const downloadDeliveryLayout=async(path:string)=>{
 const result=await admin.storage.from('shipment-excel-templates').download(path);
 if(result.error||!result.data)throw result.error??Error('공통 배송 원본을 읽을 수 없습니다.');
 return new Uint8Array(await result.data.arrayBuffer());
};

Deno.serve(createWorkbookIdentityHandler({
 url,serviceKey,Unzip,Zip,ZipPassThrough,
 prepareIdentityWorkbook:(files,route)=>prepareIdentityWorkbook(files,route,downloadDeliveryLayout),
}));
