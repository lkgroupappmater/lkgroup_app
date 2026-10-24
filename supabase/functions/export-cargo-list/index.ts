import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
import * as zip from 'npm:fflate@0.8.2';
import {createCargoListHandler} from './handler.mjs';
Deno.serve(createCargoListHandler({createClient,zip,url:Deno.env.get('SUPABASE_URL')!,anonKey:Deno.env.get('SUPABASE_ANON_KEY')!,serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!}));
