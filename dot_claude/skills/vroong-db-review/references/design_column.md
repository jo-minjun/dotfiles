# 컬럼 설계 가이드라인

## 컬럼 명명 및 생성 규칙

### 기본 원칙

1. 모든 컬럼명은 소문자로 작성하고, 단어 구분은 '_' (underscore)로 하는 snake_case 사용
2. 컬럼명은 명확하고 직관적으로 작성하여 용도를 쉽게 파악할 수 있도록 함
3. 모든 컬럼에 COMMENT를 추가하여 컬럼의 용도, 의미, 제약사항 등을 명확히 기술
4. 모든 테이블 생성 시 가장 첫 번째 컬럼은 반드시 연속된 정보를 갖는 컬럼이어야 하며 이 컬럼을 Primary Key로 지정
   - 권장(컨벤션): 컬럼 정의 끝에 `PRIMARY KEY (id)`를 별도 라인으로 정의 (컬럼 정의에는 `PRIMARY KEY`를 inline으로 붙이지 않음)
     - 예: `id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'PK',` + `PRIMARY KEY (id)`
   - 비권장: `id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY` (inline PK 선언)
   - 비권장: `pk BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY` (컬럼명이 id가 아님)
5. 다른 테이블의 PK를 ID로 사용할 경우는 "테이블명 + '_' + id"로 명명
   - 예: deliveries의 ID 사용 시 `deliveries_id`
   - 예: orders의 ID 사용 시 `orders_id`
6. 테이블명/컬럼명에 MySQL 예약어를 사용하지 않아야 함

### URI/URL/파일경로 컬럼 명명 규칙

저장 데이터의 형식에 따라 정확한 컬럼명을 사용한다.

| 저장 형식 | 컬럼명 패턴 | 예시 |
|-----------|------------|------|
| S3 URI (`s3://bucket/prefix/name`) | `{맥락}_s3_uri` | `upload_s3_uri` |
| HTTP URL | `{맥락}_url` | `thumbnail_url` |
| 파일 시스템 경로 | `{맥락}_file_path` | `config_file_path` |

- `file_path`로 명명하면서 실제로는 S3 URI를 저장하는 등 불일치를 피해야 한다

### CREATE TABLE 예시

```sql
CREATE TABLE orders (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'PK',
    deliveries_id   BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '배송 ID (deliveries.id)',
    -- 다른 컬럼들...
    PRIMARY KEY (id)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4;
```

## COMMENT 작성 가이드라인

모든 컬럼에 COMMENT를 추가하여 컬럼의 용도, 의미, 제약사항 등을 명확히 기술한다. (기본 원칙 3번 참고)

### 참조 컬럼 (FK) COMMENT

다른 테이블의 PK를 참조하는 컬럼은 COMMENT에 참조 대상을 반드시 포함한다.

#### 동일 데이터베이스 내 참조

동일 서비스(데이터베이스) 내의 테이블을 참조하는 경우 `{테이블명}.{컬럼명}` 형식을 사용한다.

```sql
-- 형식: COMMENT '설명 ({참조테이블}.{참조컬럼})'
store_id       BIGINT UNSIGNED NOT NULL COMMENT '상점 ID (stores.id)',
order_id       BIGINT UNSIGNED NOT NULL COMMENT '주문 ID (orders.id)',
```

#### 다른 서비스(서버) 참조

다른 서비스의 테이블을 참조하는 경우 `{서비스명}.{테이블명}.{컬럼명}` 형식을 사용한다. 서비스명은 데이터베이스 또는 서비스의 식별 가능한 이름을 사용한다.

```sql
-- 형식: COMMENT '설명 ({서비스명}.{참조테이블}.{참조컬럼})'
extra_fee_id         BIGINT UNSIGNED NOT NULL COMMENT '할증 ID (prime.extra_fees.id)',
extra_fee_history_id BIGINT UNSIGNED NOT NULL COMMENT '할증 이력 ID (prime.extra_fee_histories.id)',
business_owner_id    INT UNSIGNED    NOT NULL COMMENT '사업주 ID (settlement.store_business_owners.id)',
```

### 코드/열거형 컬럼 COMMENT

상태(status), 유형(type), 카테고리(category) 등 코드화된 값을 저장하는 컬럼은 가능한 값과 의미를 COMMENT에 나열한다.

#### 값의 수가 적고 안정적인 경우 (권장)

COMMENT에 모든 값을 나열한다. (STATUS 값 관리 원칙 참고)

```sql
-- TINYINT 코드
status TINYINT NOT NULL DEFAULT 0
  COMMENT '상태 (0:비활성, 1:활성, 2:대기중, 3:완료, 4:취소)',

-- 문자열 코드
change_category VARCHAR(50) NOT NULL
  COMMENT '변경 카테고리 (INITIAL_CREATION:최초 작성, CONTENT_UPDATE:내용 수정, STATUS_CHANGE:상태 변경)',
```

#### 값의 수가 많거나 자주 변경되는 경우

별도의 코드 테이블(lookup table)로 분리하고, COMMENT에는 코드 테이블을 참조한다.

```sql
region_code VARCHAR(10) NOT NULL
  COMMENT '권역 코드 (region_codes.code 참조)',
```

### 비표준 동작 컬럼 COMMENT

컬럼이 일반적인 관례와 다른 방식으로 사용되는 경우, COMMENT에 비표준 동작을 반드시 명시한다.

#### `deleted_at`의 비표준 사용

표준 soft delete에서 `deleted_at`은 한번 설정되면 되돌리지 않는다. 만약 `deleted_at`이 다시 NULL로 되돌릴 수 있는 토글 용도로 사용되는 경우, 이는 활성/비활성 상태 관리이며 반드시 COMMENT에 명시해야 한다.

```sql
-- 비표준 사용 시: COMMENT에 비표준 동작을 명시
deleted_at TIMESTAMP NULL
  COMMENT '삭제 일시. 배차 및 할증 적용 여부에 따라 soft delete 해제 될 수 있음',
```

> **참고**: `deleted_at`을 토글 용도로 사용하기보다 `is_active TINYINT(1) NOT NULL DEFAULT 1` 컬럼 사용을 권장한다. 자세한 내용은 [design_table_index.md](design_table_index.md)의 "Soft Delete 패턴" 참고.

#### 기타 비표준 사용 예시

```sql
-- NULL과 빈 문자열이 서로 다른 의미인 경우
phone_number VARCHAR(20) NULL
  COMMENT '연락처. NULL은 미수집, 빈 문자열은 본인 거부',

-- 특수한 DEFAULT 의미
retry_count INT NOT NULL DEFAULT -1
  COMMENT '재시도 횟수. -1은 미시도, 0 이상은 실제 시도 횟수',
```

### COMMENT 작성 체크리스트

| 컬럼 유형 | COMMENT 필수 포함 사항 |
|-----------|----------------------|
| 모든 컬럼 | 컬럼의 용도/의미 |
| FK 참조 컬럼 | 참조 대상 `(테이블.컬럼)` 또는 `(서비스.테이블.컬럼)` |
| 코드/열거형 컬럼 | 가능한 값과 의미 나열, 또는 코드 테이블 참조 |
| 단위가 있는 컬럼 | 단위 명시 (예: km, 원, %) |
| 비표준 동작 컬럼 | 표준과 다른 동작 설명 |

## 데이터 타입 선택 원칙

### 1. 정수형 데이터

- 작은 범위의 정수: `TINYINT` (1바이트, -128~127 또는 0~255)
- 일반적인 정수: `INT` (4바이트, -2^31~2^31-1 또는 0~2^32-1)
- 큰 범위의 정수: `BIGINT` (8바이트, -2^63~2^63-1 또는 0~2^64-1)
- 양수만 저장하는 경우 `UNSIGNED` 속성 반드시 사용
- Primary Key는 auto_increment를 기본으로 사용
  - `int unsigned`: 기본 사용 (0~4,294,967,295 범위)
  - `bigint unsigned`: 대용량 데이터 예상 시 (0~18,446,744,073,709,551,615 범위)
- IP 주소 저장 시 `INT UNSIGNED` 사용
  - `INET_ATON()`으로 IP를 INT 값으로 변환하여 저장
  - `INET_NTOA()`로 INT 값을 IP 값으로 비환하여 조회
  - VARCHAR 형태로 저장 시 15Byte 사용하나, INT UNSIGNED 형태는 4Byte 사용

### 2. 문자열 데이터

- 고정 길이 문자열: `CHAR(n)` (n은 1~255 사이)
- 가변 길이 문자열: `VARCHAR(n)` (n은 1~65,535 사이)
- CHAR, VARCHAR 사용 시 반드시 필요한 최소 길이를 지정
  - VARCHAR(255), CHAR(255)의 형태는 불필요한 인덱스 사이즈 증가 및 성능 저하 유발
  - INNODB의 INDEX PREFIX 최대 사이즈는 767 byte
    - UTF8: VARCHAR(255) 최대 사용 가능
    - UTF8MB4: VARCHAR(191) 최대 사용 가능
- 대용량 텍스트: `TEXT` 또는 `LONGTEXT`
  - TEXT, BLOB 타입의 컬럼은 최대한 사용 자제
  - 필요할 경우 테이블을 분리하여 사용
- 문자셋은 기본적으로 `utf8mb4` 사용

### 3. 날짜 및 시간 데이터

- 날짜: `DATE`
- 시간: `TIME`
- 날짜 및 시간: `TIMESTAMP` 또는 `DATETIME`
  - 날짜 형태의 컬럼은 `TIMESTAMP` 사용 권장
  - TIMESTAMP = 4byte + @
  - DATETIME = 5byte + @
- 생성 시간, 수정 시간 필드는 `TIMESTAMP` 사용 및 `DEFAULT CURRENT_TIMESTAMP` 설정

### 4. 불리언 데이터

- `TINYINT(1)` 또는 `CHAR(1)` 사용
- YES/NO 값 보다는 TRUE/FALSE 형태의 값 사용 권장
- 문자 보다는 숫자(0, 1) 사용 권장
- `NOT NULL DEFAULT 0`으로 설정
- ENUM 타입을 사용할 경우 Alter Table을 사용해야 하므로 사용하지 않는 것을 권장

### 5. 소수점 데이터

- 고정 소수점 타입 사용: `DECIMAL` (NUMERIC은 DECIMAL과 동일)
- 부동 소수점 타입 사용 금지: `FLOAT`, `DOUBLE`
  - 부동 소수점은 근사값 방식이라 잘못된 값이 나올 수 있음
  - 부동 소수점 사용이 필요한 경우 DBA와 협의 후 사용

### 6. JSON 데이터

- 복잡한 구조의 데이터는 `JSON` 타입 사용 가능
- 장점: 유연한 스키마, JSON 함수(->)를 통한 쿼리 가능
- 단점: 인덱싱이 제한적, 대량 JSON 데이터는 성능에 영향
- 사용 예시:
  - 자주 변경되는 속성 집합
  - 중첩된 데이터 구조
  - 설정 정보 저장
- JSON 컬럼은 필요한 경우 가상 컬럼과 함께 사용하여 인덱싱 가능

### 7. 이진 데이터 타입

- `BINARY`/`VARBINARY`: 고정/가변 길이 이진 데이터
- `BLOB`: 대용량 이진 데이터
- 사용 사례:
  - UUID 저장: `BINARY(16)` 사용 (`CHAR(36)` 대비 저장 공간 절약)
    - 참고 문서: [MySQL 공식 문서 - 효율적인 UUID 저장](https://dev.mysql.com/blog-archive/mysql-8-0-uuid-support/)
    - 저장 공간: CHAR(36)은 36바이트 사용, BINARY(16)은 16바이트만 사용
    - 성능: 인덱스 크기 감소로 I/O 및 메모리 사용량 감소, 조회 성능 향상
  - 암호화된 데이터: `VARBINARY` 사용

## 컬럼 타입 변경 시 인덱스 영향도 확인

컬럼의 데이터 타입을 변경할 때 해당 컬럼에 인덱스(특히 UNIQUE KEY)가 존재하는지 반드시 확인해야 한다.

- 인덱스가 존재하는 컬럼의 타입 변경은 인덱스 리빌드를 수반하며, `ALGORITHM=COPY`가 필요할 수 있다
- 사전 확인: `SHOW INDEX FROM table_name` 으로 해당 컬럼을 포함하는 모든 인덱스를 확인
- 영향도 문서화: 리빌드 대상 인덱스 목록, 예상 소요 시간, 서비스 영향 범위를 DDL 요청에 포함
- "인덱스 영향 없음" 판단은 `SHOW INDEX` 결과를 근거로 제시해야 한다

## 거리 데이터 표준

### 표준 컬럼 타입

- 거리 컬럼은 `DECIMAL(10,5)`를 사용하며, 단위는 **킬로미터(km)**
- 해상도: 0.00001 km = 0.01 m (1 cm)
- 최대값: 99,999.99999 km
- UNSIGNED는 사용하지 않는다 — DECIMAL에 UNSIGNED를 적용하면 Aurora MySQL 호환성 및 향후 마이그레이션에서 문제가 될 수 있다
- MySQL 저장 크기: 6바이트

```sql
-- 표준 거리 컬럼 정의
origin_to_dest_distance_km DECIMAL(10,5) NOT NULL DEFAULT 0.00000
  COMMENT '출발지에서 도착지까지의 거리(km)',
```

### 사용 금지 타입

- `DOUBLE`, `FLOAT`: 부동 소수점은 근사값 방식으로 정밀도 손실 발생 (5. 소수점 데이터 참고)
- `INT` (미터 단위): 소수점 이하 정밀도 부재로 계산 시 정밀도 보장 불가
- `VARCHAR`: 숫자 연산 불가, 타입 불일치

### 정밀도 요구사항

비즈니스 요구 정밀도는 1미터이며, 표시되는 거리 값은 실제 값과 **±0.5m** 이내여야 한다. 이 정밀도는 합산 등 계산을 거쳐도 유지되어야 한다.

저장된 각 값은 최대 ±(해상도 / 2)의 반올림 오차를 가진다. N개의 값을 합산할 경우 최악의 경우 오차는 ±N × (해상도 / 2)까지 누적될 수 있다.

| 합산 규모 | 예시 | 최악의 경우 오차 | ±0.5m 충족 여부 |
|-----------|------|-----------------|----------------|
| 1건 | 단일 거리 | ±0.005m | 충족 (100배 여유) |
| 10건 | 경로 구간 | ±0.05m | 충족 (10배 여유) |
| 100건 | 일일 기사 합산 | ±0.5m | 충족 (정확히 만족) |
| 1,000건 | 월간 합산 | ±5m | 미충족 |

100건 이상의 합산에서 ±0.5m이 필요한 경우, 저장된 값이 아닌 원본 소스 데이터로부터 합산해야 한다.

### 컬럼 명명 규칙

- 패턴: `{맥락}_distance_km`
- `_km` 접미사는 **필수** — 단위가 없는 `distance` 컬럼명은 본 표준에 부합하지 않음
- 범위 컬럼: `{맥락}_distance_km_min`, `{맥락}_distance_km_max`

| 컬럼명 | 설명 |
|--------|------|
| `origin_to_dest_distance_km` | 출발지에서 도착지까지의 거리 |
| `agent_to_origin_distance_km` | 기사의 현재위치에서 출발지까지의 거리 |
| `deliverable_distance_km` | 배달가능 거리 |
| `distance_km` | 테이블명으로 맥락이 명확한 경우 |

### COMMENT 규칙

- 모든 거리 컬럼의 COMMENT에 단위를 반드시 포함
  - 예: `COMMENT '출발지에서 도착지까지의 거리(km)'`
  - 예: `COMMENT '기사의 현재위치에서 출발지까지의 거리(km)'`

### DEFAULT 값 규칙

| 경우 | DEFAULT |
|------|---------|
| 선택적 거리 (생성 시 미확정) | `DEFAULT NULL` |
| 필수 거리 (0이 의미 있는 경우) | `NOT NULL DEFAULT 0.00000` |
| 비즈니스 기본값이 있는 임계값 | `NOT NULL DEFAULT {값}` (소수점 5자리) |

- `DEFAULT 0` 또는 `DEFAULT 0.0` 사용 금지 — 반드시 선언된 scale에 맞춰 `0.00000` 사용

### 거리 컬럼 설계 예시

```sql
-- 기본 거리 컬럼
origin_to_dest_distance_km DECIMAL(10,5) NOT NULL DEFAULT 0.00000
  COMMENT '출발지에서 도착지까지의 거리(km)',

-- 선택적 거리 컬럼
agent_to_origin_distance_km DECIMAL(10,5) DEFAULT NULL
  COMMENT '기사의 현재위치에서 출발지까지의 거리(km)',

-- 범위 설정 컬럼
agent_to_origin_distance_km_min DECIMAL(10,5) NOT NULL DEFAULT 0.50000
  COMMENT '기사-출발지까지 거리 최소값(km)',
agent_to_origin_distance_km_max DECIMAL(10,5) NOT NULL DEFAULT 1.00000
  COMMENT '기사-출발지까지 거리 최대값(km)',
```

### 반올림 및 집계 규칙

#### 저장 시

- 컬럼 타입의 전체 해상도(소수점 5자리)로 저장
- 소스가 더 높은 정밀도를 제공하는 경우, 저장 경계에서 HALF_UP 반올림 적용
- 소스가 미터 단위인 경우: 1000으로 나누어 km로 변환

#### 표시 시

- 애플리케이션은 사용자 표시 목적으로 반올림 가능 (예: "1.3 km")
- 비즈니스 로직은 도메인 요구에 따라 더 큰 단위 사용 가능 (예: 100m 단위 요금 구간)

#### 집계 시

**반올림된 소계와 합계를 동시에 표시하는 경우: 먼저 반올림한 후 합산한다.**

```
저장 값: 1.35000 km, 1.55000 km, 2.05000 km

올바른 방식 (반올림 후 합산):
  표시 (0.1 km): 1.4 + 1.6 + 2.1 = 5.1 km  ← 사용자에게 보이는 값

잘못된 방식 (합산 후 반올림):
  합산: 4.95000 km → 반올림 → 5.0 km  ← 소계의 합과 불일치
```

사용자는 표시된 소계의 합이 표시된 합계와 일치할 것으로 기대한다.

## STATUS 값 관리 원칙

1. 코드화 가능한 컬럼(status, type, category 등)은 `TINYINT NOT NULL DEFAULT 0` 사용
   - 예: `status TINYINT NOT NULL DEFAULT 0 COMMENT '상태(0:비활성, 1:활성, 2:대기중, 3:완료, 4:취소)'`
   - 예: `type TINYINT NOT NULL DEFAULT 0 COMMENT '타입(0:기본, 1:프리미엄, 2:기업용)'`
2. 해당 코드의 의미는 반드시 COMMENT에 포함
3. 각 코드에 해당하는 문자열 메시지는 애플리케이션 코드에서 관리
4. 기본값(DEFAULT)는 가장 초기 상태 값으로 설정
5. 사용하지 않는 값(예약된 값)을 명확히 구분하여 문서화

### STATUS 컬럼 설계 예시

```sql
-- 권장 방식: TINYINT 사용
status TINYINT NOT NULL DEFAULT 0 COMMENT '상태(0:비활성, 1:활성, 2:대기중, 3:완료, 4:취소)',
```

## 문자셋 및 콜레이션 선택

- 기본적으로 `utf8mb4` 문자셋과 `utf8mb4_general_ci` 콜레이션을 공통규격으로 사용
  - `utf8mb4`: 모든 유니코드 문자(이모지 포함) 지원
  - `utf8mb4_general_ci`: 빠른 성능과 대부분의 비교 작업에 충분함
- 모든 테이블과 컬럼에서 동일한 콜레이션을 사용하여 조인 성능 및 일관성 유지

## 가상 컬럼과 생성된 컬럼

- 다른 컬럼에서 계산된 값을 저장하는 컬럼 유형
- 종류:
  - `VIRTUAL`: 조회 시 계산, 디스크에 저장하지 않음
  - `STORED`: 계산 후 디스크에 저장, 조회 성능 향상
- 사용 예시:
  - JSON 컬럼의 특정 속성을 추출하여 인덱싱
  - 복잡한 계산 결과를 미리 저장
  - 데이터 정규화와 쿼리 성능 간 균형

```sql
-- 생성된 컬럼 예시 (JSON 필드에서 값 추출)
json_data JSON,
user_id INT GENERATED ALWAYS AS (json_data->>'$.user_id') STORED,
INDEX idx_user_id (user_id)
```

## DEFAULT 값 설정 원칙

1. 모든 컬럼은 가능한 `NOT NULL`로 설정하고 적절한 DEFAULT 값 지정
2. 생성 시간 (`created_at`)은 `TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP`
3. 수정 시간 (`updated_at`)은 다음 두 가지 방식 중 하나를 선택하여 정의
   - `TIMESTAMP NULL` - 최초 생성 시점에는 NULL이고, 수정 시에만 값이 설정됨
   - `TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP` - JPA 등 ORM 프레임워크에서 생성 시점에도 값을 설정하는 경우 사용
4. 삭제 시간 (`deleted_at`)은 `TIMESTAMP NULL` - 삭제가 발생하기 전까지는 NULL 상태로 유지됨
5. 불리언 필드는 `TINYINT(1) NOT NULL DEFAULT 0`
6. 코드화 가능한 컬럼(status, type, category 등)은 가장 초기 상태 또는 기본 값을 DEFAULT로 설정 (예: `TINYINT NOT NULL DEFAULT 0`)
   - 가능한 코드 값의 의미는 항상 COMMENT에 포함하여 기록 (예: `status TINYINT NOT NULL DEFAULT 0 COMMENT '상태(0:비활성, 1:활성, 2:대기중, 3:완료, 4:취소)'`)
   - 각 코드에 해당하는 문자열 메시지는 데이터베이스가 아닌 애플리케이션 코드에서 관리

### 시간 관련 필드 설계 예시

#### 방식 1: updated_at을 NULL 허용으로 정의 (수정 여부 추적이 필요한 경우)

```sql
-- 레코드 생성 시간 (생성시점 자동 기록)
created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시간',

-- 레코드 수정 시간 (수정 발생 전까지 NULL)
updated_at TIMESTAMP NULL COMMENT '마지막 수정 시간',

-- 레코드 삭제 시간 (삭제 발생 전까지 NULL)
deleted_at TIMESTAMP NULL COMMENT '삭제 시간',
```

이 방식을 사용하면 다음과 같은 이점이 있습니다:
1. 레코드가 수정된 적이 있는지 확인 가능 (`updated_at IS NOT NULL`)
2. 삭제된 레코드 식별 및 소프트 삭제 구현 가능 (`deleted_at IS NULL`)
3. 레코드의 전체 생명주기 추적 가능

#### 방식 2: updated_at을 NOT NULL로 정의 (JPA/ORM 프레임워크 사용 시)

```sql
-- 레코드 생성 시간 (생성시점 자동 기록)
created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시간',

-- 레코드 수정 시간 (생성시점에도 값이 설정됨)
updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '마지막 수정 시간',

-- 레코드 삭제 시간 (삭제 발생 전까지 NULL)
deleted_at TIMESTAMP NULL COMMENT '삭제 시간',
```

JPA 등 ORM 프레임워크에서는 `@UpdateTimestamp`, `@LastModifiedDate` 등의 어노테이션을 사용하여 엔티티 생성 시점에도 `updated_at`에 값을 설정합니다. 이 경우 NOT NULL로 정의하는 것이 애플리케이션 동작과 일관성을 유지합니다.

## 인덱스 명명 및 생성 규칙

### 인덱스 이름 정의

- 모든 INDEX의 이름은 대문자를 사용하며 각 인덱스별 접두어는 아래와 같이 지정
  - Unique INDEX: `UK_`
  - INDEX: `IDX_`
- 인덱스 생성 시 Table 명은 미포함 하며, 컬럼의 이름을 넣어서 생성
- 2개 이상의 컬럼으로 생성할 경우 컬럼명에서 '_'를 제거 후 생성
  - 컬럼 이름: `order_id`
    예) `IDX_ORDER_ID`
  - 컬럼 이름: `order_id`, `agent_id`
    예) `IDX_ORDERID_AGENTID`

### 인덱스 생성 규칙

- 인덱스 생성 시 반드시 Cardinality 체크 후 생성
  - 공식: Cardinality = distinct row count / total row count
  - 0.85 이상인 컬럼에 대해서 생성 권장
- 여러 컬럼에 대해서 인덱스를 생성할 경우
  - Cardinality가 높은 컬럼부터 낮은 컬럼으로 생성
  - 예) a_col: 0.9, b_col: 0.85, c_col: 0.02
    `CREATE INDEX IDX_ACOL_BCOL_CCOL ON test (a_col, b_col, c_col)`
- 가능하면 1개의 테이블에는 PK(id, auto_increment, 인공키)와 논리적 PK인 Unique Index를 1개를 같이 만드는 것을 권장

### 인덱스 최적화를 위한 컬럼 선택

- 인덱스로 자주 사용되는 컬럼은 가능한 작은 데이터 타입 선택
  - 예: `VARCHAR(255)` 대신 실제 필요한 최소 길이 사용
  - 예: UUID를 저장할 때 `CHAR(36)` 대신 `BINARY(16)` 사용
- 정수형 기본 키는 문자열 기본 키보다 조인 성능이 우수함
- 복합 인덱스 컬럼 순서는 카디널리티(고유값 수)가 높은 컬럼을 앞에 배치
- 인덱스 컬럼에는 가능한 `NOT NULL` 제약 추가 (NULL 값은 인덱스 효율성 저하)

## Aurora MySQL 3.x 특화 고려사항

- Aurora 스토리지 엔진의 특성을 고려한 설계:
  - 대규모 BLOB/TEXT 컬럼은 성능에 영향을 줄 수 있음
  - 트랜잭션이 큰 BLOB 데이터를 다루는 경우 커밋 시간 지연 가능성
- 복제 지연을 최소화하기 위한 설계:
  - 대량의 가변 길이 컬럼(VARCHAR, TEXT, BLOB)이 있는 테이블은 복제 지연 가능성
  - 이진 로그 크기를 고려한 컬럼 설계
- 인스턴스 리플리케이션 고려사항:
  - 대용량 트랜잭션은 복제 지연 가능성

## 암호화 컬럼 적용 규칙

### 암호화 컬럼 명명

- 암호화 컬럼을 생성시 컬럼명 뒤에 "_enc"를 붙여서 사용
  - 예: phone_num --> phone_num_enc

### 암호화 컬럼 문서화

- 암호화 컬럼(`_enc`)에는 반드시 COMMENT를 작성해야 하며, 다음 정보를 포함해야 합니다:
  1. 암호화 전 원본 데이터 타입 (예: VARCHAR(20))
  2. 컬럼의 용도 설명
- COMMENT 작성 예시:
  ```sql
  phone_num_enc VARBINARY(256) NOT NULL COMMENT '전화번호(암호화 전: VARCHAR(20))',
  email_enc VARBINARY(512) NOT NULL COMMENT '이메일 주소(암호화 전: VARCHAR(100))',
  address_detail_enc VARBINARY(1024) NULL COMMENT '상세 주소(암호화 전: VARCHAR(255))',
  ```

### 암호화 데이터 길이 계산

- 데이터를 암호화시, 사용하고자하는 크기에 맞는 사이즈를 계산해서 사용
- 길이 계산 공식: (키 크기(비트) / 8) - (2 * 해시 길이(비트)/8) - 2
  - 예시: SHA-256을 사용하는 RSA_2048의 경우 바이트 단위의 최대 일반 텍스트 크기는
    (2048/8) - (2 * 256/8) - 2 = 190바이트
  - 신중한 배치 사이즈 선택 (너무 크면 복제 지연, 너무 작으면 성능 저하)