import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
import {Unzip,Zip,ZipPassThrough} from 'npm:fflate@0.8.2';
import {createWorkbookFinalizer} from '../export-shipment-excel/workbook-finalizer-handler.mjs';
import {finalizeWorkbook} from '../export-shipment-excel/finalize-workbook.ts';

Deno.serve(createWorkbookFinalizer({
 url:Deno.env.get('SUPABASE_URL'),serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
 createClient,Unzip,Zip,ZipPassThrough,finalizeWorkbook,
}));
