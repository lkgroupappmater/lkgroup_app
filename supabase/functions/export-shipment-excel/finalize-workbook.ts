import {applyDiscountMatching} from './discount-workbook.mjs';
import {finishTemplateStyleGuard} from './template-style-guard.mjs';
import {FREIGHT_MINIMUM_VERSION} from './freight-minimum.mjs';
import {validateWorkbookFormulas} from './workbook-integrity.mjs';
import {validateWorkbookPackage} from './workbook-package.mjs';
import {consumeWorkbookFinalization} from './finalization-preparation.mjs';
import {upgradeStatementMacros} from './statement-macros.mjs';

export function finalizeWorkbook(files:Record<string,Uint8Array>){
 const prepared=consumeWorkbookFinalization(files);
 const discount=applyDiscountMatching(files);
 const integrity={...validateWorkbookFormulas(files),discount_identity:discount,freight_minimum_version:FREIGHT_MINIMUM_VERSION,freight_minimum_changed:prepared.freightMinimumChanged};
 upgradeStatementMacros(files);
 const templateStyles={...finishTemplateStyleGuard(files),capture_stage:prepared.captureStage};
 return {...integrity,template_styles:templateStyles,calculation_chain_reset:prepared.calculationChain,package_integrity:validateWorkbookPackage(files)};
}
