from pathlib import Path
import shutil
R=Path.cwd()
src=Path(__file__).resolve().parent/'customer_list_management_screen.dart'
dst=R/'lib/screens/customer_list_management_screen.dart'
if not dst.exists(): raise SystemExit('customer_list_management_screen.dart not found')
shutil.copy2(src,dst)
s=dst.read_text(encoding='utf-8')
checks=[
('image save','Future<void> _saveImage()' in s),
('pdf save','Future<void> _savePdf()' in s),
('excel-like columns',"['영수증 번호','고객명/회사명','연락처','구획(Zone)','수량','비고']" in s),
('receipt zone edit',"'receipt_number':nr,'unloading_zone':nz" in s),
('bottom buttons',"'이미지 저장'" in s and "'PDF 저장 / 프린트'" in s),
]
print('PATCH191B VERIFY'); bad=[]
for n,o in checks:
 print(('[OK] ' if o else '[FAIL] ')+n)
 if not o: bad.append(n)
if bad: raise SystemExit('VERIFY FAILED: '+', '.join(bad))
print('PATCH191B VERIFIED OK')
