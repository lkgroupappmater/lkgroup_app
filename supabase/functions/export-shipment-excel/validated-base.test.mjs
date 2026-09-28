import test from 'node:test';
import assert from 'node:assert/strict';
import {canReuseValidatedBase} from './validated-base.mjs';
test('only current verified BASE bytes can bypass recalculation',()=>{
 const base={storage_path:'base/sea/current.xlsm',policy_summary:{automation_version:'v5',validated_source_revision:12,integrity:{stored_download_verified:true,shared_formula_errors:0}}};
 const sync={status:'ready',revision:12,completed_revision:12};
 assert.equal(canReuseValidatedBase(base,sync,'v5'),true);
 for(const changed of [{revision:13},{status:'pending'},{completed_revision:11}])assert.equal(canReuseValidatedBase(base,{...sync,...changed},'v5'),false);
 assert.equal(canReuseValidatedBase(base,sync,'v6'),false);
 assert.equal(canReuseValidatedBase({...base,policy_summary:{...base.policy_summary,integrity:{shared_formula_errors:0}}},sync,'v5'),false);
 assert.equal(canReuseValidatedBase({...base,storage_path:'database://abc'},sync,'v5'),false);
});
