# CargoFlow 데이터·권한 운영 정책

## 1. 권장 파일명

엑셀 파일명은 사람이 읽기 쉬우면서도 SQL 업로드 시 자동 분류할 수 있도록 다음 규칙을 사용합니다.

```text
{route_code}_Y{year}_{voyage}_shipments.xlsx
```

예시:

```text
KR-LA-SEA_Y2026_V001_shipments.xlsx
KR-LA-AIR_Y2026_V001_shipments.xlsx
LA-KR-AIR-EXPRESS_Y2026_V001_shipments.xlsx
LA-TH-LAND_Y2026_V001_shipments.xlsx
LA-VN-LAND_Y2026_V001_shipments.xlsx
LA-CN-LAND_Y2026_V001_shipments.xlsx
LA-KH-LAND_Y2026_V001_shipments.xlsx
```

노선 코드는 다음처럼 고정합니다.

| 화면 표시 | route_code |
|---|---|
| 한국->라오스 해상 | `KR-LA-SEA` |
| 한국->라오스 항공 | `KR-LA-AIR` |
| 라오스->한국 항공 특송 | `LA-KR-AIR-EXPRESS` |
| 라오스->태국 육로 | `LA-TH-LAND` |
| 라오스->베트남 육로 | `LA-VN-LAND` |
| 라오스->중국 육로 | `LA-CN-LAND` |
| 라오스->캄보디아 육로 | `LA-KH-LAND` |

`V001`은 01항차이며, `V002`, `V003`처럼 증가시킵니다. 파일명에 한글, 공백, `->`, 쉼표는 사용하지 않는 것을 권장합니다.

## 2. 엑셀 열 이름

모든 노선 파일은 같은 열 순서를 유지해야 웹 관리자 업로드와 SQL/CSV 변환이 안전합니다.

```text
route,year,voyage,box_number,invoice_number,consignee_name,consignee_phone,
received_at,weight_kg,width_cm,length_cm,height_cm,quantity,receipt_number,
origin,destination,status,cargo_type,notes,customer_email
```

- `route/year/voyage`는 파일명에서 자동으로 채워도 되지만, 행에도 넣어 검증합니다.
- `customer_email`은 업로드 시 `profiles.email`과 매칭하여 `customer_id`로 변환합니다.
- 실제 첨부 엑셀 파일은 이번 요청 메시지에 포함되어 있지 않으므로, 위 열은 현재 SQL 구조 기준의 권장 표준입니다. 실제 파일을 받으면 열 매핑표를 확정해야 합니다.
- 송장번호·박스번호·영수증 번호는 엑셀에서 숫자로 저장하지 말고 텍스트로 저장합니다(앞자리 0 보존).

## 3. 권한

| 역할 | 화물 검색 | 검색 범위 | 화물 관리/선택 | 운임 확인 | 일정·공지 관리 |
|---|---|---|---|---|---|
| 비로그인 | 불가 | 없음 | 불가 | 불가 | 공개 읽기만 |
| 일반 회원(member) | 가능 | `customer_id = 본인` | 선택된 본인 화물 | 가능 | 읽기만 |
| 관리자 직원(staff) | 가능 | 전체 | 전체 | 가능 | 작성·수정 가능 |
| 관리자 총괄(admin) | 가능 | 전체 | 전체 | 가능 | 작성·수정·권한 관리 |
| 협력/파트너사(partner) | 가능 | 전체 | 전체 | 가능 | 읽기, 화물 업무 범위에 따라 쓰기 |

화물 조회에서 일반 회원의 이름/연락처는 가입 프로필의 값을 기본 입력합니다. 그러나 최종 보안은 화면이 아니라 Supabase RLS가 담당하며, 회원이 다른 사람의 `customer_id`를 바꾸어도 다른 화물이 노출되지 않습니다.

## 4. 총괄 관리자 계정 생성

첫 총괄 관리자는 앱에서 `admin` 역할로 가입시키지 않습니다. 신규 가입 트리거는 보안을 위해 모든 신규 사용자를 `member`로 만들기 때문입니다.

1. Supabase Dashboard → **Authentication → Users → Add user**에서 관리자 이메일/임시 비밀번호를 생성합니다. 또는 앱에서 일반 회원으로 가입합니다.
2. 생성된 이메일을 확인한 뒤 SQL Editor에서 아래를 실행합니다.

```sql
select id, email, role, approval_status
from public.profiles
where lower(email) = lower('admin@example.com');

update public.profiles
set role = 'admin', approval_status = 'approved', updated_at = now()
where lower(email) = lower('admin@example.com');
```

3. 앱에서 해당 이메일과 비밀번호로 로그인합니다.
4. 로그인 직후 앱이 `profiles.role = 'admin'`을 읽어 총괄 관리 화면을 표시합니다.

`service_role` 키나 DB 비밀번호를 앱에 넣지 않습니다. 직원/파트너 계정은 일반 회원 가입 후 총괄 관리자가 프로필 역할을 직접 바꾸거나, 현재 앱의 계정 발급 요청 흐름을 사용합니다.

## 5. 운임 확인

현재 UI는 선택된 화물의 체크와 `운임 확인` 버튼 활성화까지만 담당합니다. 노선별 단가·최소 운임·부피중량·추가 비용은 실제 운임표를 받은 뒤 별도 `freight_rates` 테이블과 서버 계산 로직으로 추가합니다. 앱에서 단가를 하드코딩하지 않는 것을 원칙으로 합니다.

