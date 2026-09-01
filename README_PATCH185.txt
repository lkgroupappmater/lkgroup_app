Patch185 - complete the partially applied Patch184

Patch184 stopped at the management-menu step, so earlier edits may already be
present locally. Patch185 does NOT redo them blindly.

It:
1. Finds the actual local menu file containing BOTH:
   하역 자료 관리
   UnloadingListManagementScreen
2. Uses parenthesis parsing to identify the exact enclosing menu function call,
   regardless of whether the app uses ListTile/Card/custom builder.
3. Clones that exact menu item as 고객 리스트.
4. Verifies all important Patch184 changes:
   - customer screen exists
   - menu navigation exists
   - statement % is in the 2/3 column
   - CEO can be used as an exact strong identity token so Park's actual chart
     percentage can resolve (NO hardcoded 100%)
   - Excel normal A/B/C/F formula preservation logic exists

Only after all five checks pass does the script print:
PATCH185 VERIFIED OK

After that:
flutter analyze
npx supabase functions deploy export-shipment-excel
flutter run

SQL none.
V00 reupload none.
Recalculate none.
