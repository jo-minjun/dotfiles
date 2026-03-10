# 테이블 및 인덱스 설계 가이드라인

> **참고**: 컬럼 설계와 관련된 자세한 가이드라인은 [design_column.md](design_column.md) 문서를 참고하십시오. 테이블 구조 설계 시 컬럼 데이터 타입 선택, 컬럼 명명 규칙, DEFAULT 값 설정 원칙 등을 포함하고 있습니다.

## 1. 테이블 설계 가이드라인

### 1.1 테이블 명명 규칙

- **기본 원칙**
  - 모든 문자는 소문자 사용 (데이터베이스, 테이블, 컬럼, 뷰, UDF, Procedure)
  - MySQL 예약어와 동일한 이름 사용 금지 ([MySQL 8.0 키워드 목록](https://dev.mysql.com/doc/refman/8.0/en/keywords.html) 참조)
  - 단어 구분은 '_' (underscore)로 하는 'snake_case' 사용

- **테이블 명명 규칙**
  - 테이블명은 복수형 사용 (예: users, orders, deliveries)
  - 약어 사용은 고유 명사에 한해 허용 (예: vip_members)
  - 테이블 생성 시 반드시 Table Comment 추가
  - 테이블 캐릭터셋은 Database Character set을 상속 (utf8mb4 권장)

### 1.2 테이블 구조 설계

- **정규화 수준**
  - 기본적으로 3NF(Third Normal Form)까지 정규화 권장
  - 성능상 필요한 경우 선택적 반정규화 고려
  - 데이터 중복과 정합성 사이의 균형 유지

- **Soft Delete 패턴**
  - 데이터 삭제 시 물리적 삭제 대신 논리적 삭제(Soft Delete) 권장
  - `deleted_at`, `deleted_by` 컬럼을 추가하여 삭제 정보 관리
  - 삭제된 데이터 조회 시 WHERE 절에 `deleted_at IS NULL` 조건 추가

- **Soft Delete 테이블 인덱스 설계**
  - `deleted_at`은 거의 항상 WHERE 절의 필터 조건으로 사용되며, ORDER BY에는 사용되지 않는다
  - `deleted_at`을 복합 인덱스의 중간 또는 뒤쪽에 배치한다
  - 동일한 선행 컬럼을 공유하는 복수의 인덱스를 생성하기보다, 하나의 복합 인덱스로 통합 가능한지 검토한다
    - 예: `IDX_ORDERID_DELETEDAT`과 `IDX_ORDERID_FORFRIENDS_DELETEDAT`는 `IDX_ORDERID_DELETEDAT_FORFRIENDS`로 통합 가능
  - `deleted_at IS NULL` 조건이 항상 포함되는 쿼리 패턴이라면, 해당 조건을 포함하는 복합 인덱스를 설계한다

- **Soft Delete와 UNIQUE KEY 설계**
  - `deleted_at`이 토글 용도로 사용되는 경우 (활성/비활성 상태 관리, [컬럼 설계 가이드라인](design_column.md#deleted_at의-비표준-사용) 참고), UNIQUE KEY에서 "삭제 취소" 시나리오를 반드시 고려해야 한다
  - 삭제된 레코드와 동일한 키 조합이 재입력(또는 재활성화)될 가능성이 있다면, UNIQUE KEY에 `deleted_at`을 포함하거나 설계를 재검토한다

- **대용량/대량 트랜잭션 테이블 관리**
  - 대량 트랜잭션: 1일 10만건 이상 또는 1GB 이상 증가
  - 대용량 테이블: 5년 예상 용량 100GB 이상 또는 5000만건 이상
  - 이러한 테이블 생성 시 DBA와 사전 협의 필수

### 1.3 테이블 관계 설계

- **관계 표현**
  - 다른 테이블의 PK를 참조하는 경우 `{참조테이블명}_id` 형식으로 네이밍 (예: client_id, order_id)
  - 다대다(N:M) 관계는 중간 테이블 사용 (예: order_items)
  - 계층 구조는 자기 참조 관계 사용 (예: parent_id)

- **관계 제약 조건**
  - 관계 무결성 보장을 위해 외래 키 설정 권장
  - 성능에 민감한 경우 애플리케이션 레벨에서 무결성 관리 고려

### 1.4 파티셔닝 전략

- **파티셔닝 대상**
  - 오더와 비례해서 혹은 오더수 이상으로 증가하는 테이블의 경우 파티션 구조 및 데이터 보관 정책 필요
  - 대용량 테이블 (100GB 이상)
  - 이력성 데이터가 많은 테이블

- **파티셔닝 방식**
  - **RANGE 파티셔닝**: 날짜/시간 기반 파티셔닝에 적합 (created_at, order_date 등)
    - 예: `PARTITION BY RANGE (UNIX_TIMESTAMP(created_at))`
  - **LIST 파티셔닝**: 불연속 카테고리 값 기반 파티셔닝 (status, type 등)
    - 예: `PARTITION BY LIST (status)`
  - **HASH 파티셔닝**: 데이터 규모가 큰 경우 고르게 분산 필요시 (customer_id 등)
    - 예: `PARTITION BY HASH (customer_id) PARTITIONS 4`
  - **KEY 파티셔닝**: HASH와 비슷하지만 MySQL이 내부 해시 함수 사용
    - 예: `PARTITION BY KEY (order_id) PARTITIONS 4`

- **파티셔닝 필수 주의사항**
  - **파티션 키 제약사항**: 파티션 키는 PRIMARY KEY 또는 UNIQUE KEY의 일부여야 함
    ```sql
    -- 예: id와 created_at을 포함한 PK
    PRIMARY KEY (id, created_at),
    PARTITION BY RANGE (UNIX_TIMESTAMP(created_at))
    ```
  - **파티션 프루닝 활용**: 파티션 키가 WHERE 절에 필수 검색조건으로 들어와야 함 (그렇지 않으면 모든 파티션 파일/인덱스 접근 필요)
    ```sql
    -- 나쁘음 (프루닝 미적용)
    SELECT * FROM orders WHERE customer_id = 1001;

    -- 좋음 (프루닝 적용)
    SELECT * FROM orders WHERE created_at >= '2023-01-01';
    ```
  - **유니크 인덱스 사용 자제**: 파티션 테이블에서 유니크 인덱스 사용은 권장하지 않음 (전 파티션에 대한 CRUD 유지관리 비용 문제)
  - **MAXVALUE 파티션 관리**: 기본적으로 MAXVALUE 파티션은 사용하지 않는 것이 좋지만, 관리의 부재로 테이블 파티션 사용량이 모니터링되지 않을 가능성이 있다면 사용을 고려할 수 있음
    - **MySQL 8.0/Aurora MySQL 3.x 전문가 관점**:
      - MAXVALUE는 이론적으로는 안전장치지만, 실제 환경에서는 심각한 성능 저하와 테이블 잠금 문제를 초래할 수 있음

      - Aurora MySQL 3.x에서는 보다 나은 번동성(flexibility)을 제공하지만, 대용량 테이블의 패턴과 트래픽에 대한 깊은 이해가 반드시 필요함

    - **주의사항**: MAXVALUE 파티션을 사용하는 경우 새 파티션 추가 시
      1. 메타락 독점(lock) 방지를 위해 데이터가 적은 시간대(특히 시스템 load가 낮은 시간대)에 작업 수행
      2. 계획된 파티션 생성을 스크립트로 자동화하여 작업 오류 방지
      3. 메타락 최소화를 위해 ALTER TABLE 명령어 작업 전 테이블 가용성 확인
      4. ALGORITHM=INPLACE, LOCK=NONE 옵션을 사용하여 작업 수행 시도 (MySQL 8.0/Aurora MySQL 3.x에서 지원)
      5. 분산 시스템의 경우 상위 레벨 해시 파티셔닝을 사용하여 작업 분산 고려

- **파티션 관리 및 운영**
  - **정기적 파티션 생성**: 파티션은 주기적으로 생성하거나 자동생성 스크립트 구현
    - **파티션 네이밍 규칙**: 테이블명_part_연도월 형식 사용 (예: orders_part_202412)
    ```sql
    -- 예: 매월 파티션 자동 생성 스크립트 로직
    ALTER TABLE orders ADD PARTITION (PARTITION orders_part_202412 VALUES LESS THAN (UNIX_TIMESTAMP('2025-01-01')));
    ```
    - **저장 프로시저 활용**: 파티션 자동 생성을 위한 저장 프로시저 구현 권장
    ```sql
    -- SP_TB_ADD_PARTITION 프로시저 정의 예시
    CREATE DEFINER=`admin`@`%` PROCEDURE SP_TB_ADD_PARTITION(
        IN p_schema_name VARCHAR(64) COMMENT '스키마(데이터베이스) 이름',
        IN p_table_name VARCHAR(64) COMMENT '테이블 이름',
        OUT p_result INT COMMENT '처리 결과 (1: 성공, 0: 실패)'
    )
    COMMENT '테이블에 월별 파티션을 추가하는 프로시저'
    LANGUAGE SQL
    NOT DETERMINISTIC
    CONTAINS SQL
    SQL SECURITY DEFINER
    BEGIN
        -- 파티션 생성 로직
        -- REORGANIZE PARTITION pmax를 통해 새 파티션 추가
    END;
    ```
    - **프로시저 특성 정의**: 파티션 관리 프로시저는 다음과 같은 특성을 명시적으로 정의
      - `LANGUAGE SQL`: SQL 언어로 작성됨
      - `NOT DETERMINISTIC`: 동일 입력에도 다른 결과 반환 가능(날짜 기반 로직)
      - `CONTAINS SQL`: 데이터를 읽거나 수정하지만 외부 호출 없음
      - `SQL SECURITY DEFINER`: 프로시저 정의자 권한으로 실행
  - **자세한 파티션 관리 프로시저 가이드**: [파티션 관리 프로시저 상세 가이드](../tools/script/mysql_partition_management_procedures.md)
  - **파티션 삭제 순서**: 삭제시 TRUNCATE 후 DROP 수행 (메타데이터 잠금 최소화)
    ```sql
    -- 예: 파티션 삭제 방법
    ALTER TABLE orders TRUNCATE PARTITION orders_part_202301;
    ALTER TABLE orders DROP PARTITION orders_part_202301;
    ```
  - **데이터 보관 정책**: 오래된 데이터(5년 이상)는 분리보관 고려
    - 예: 과거 데이터를 별도 아카이브 테이블로 이동 후 원본 테이블에서 삭제

- **파티션 성능 고려사항**
  - **파티션 파일 구조**: 각 파티션은 개별 파일과 인덱스로 관리 (글로벌 인덱스 아님)
  - **파티션 구성 제한**: MySQL 8.0/Aurora MySQL 3.x에서 최대 8,192개 가능 (Aurora MySQL 3.x의 경우도 동일한 제한 적용)
  - **파티션 분포**: 데이터가 특정 파티션에 집중되지 않도록 설계 (Hot Partition 문제 회피)
  - **적절한 파티션 크기**: 파티션당 10-30GB 정도로 유지하는 것이 관리 및 성능 관점에서 적합

## 2. 인덱스 설계 가이드라인

### 2.1 Primary Key 설계

- **기본 원칙**
  - auto_increment 사용
  - 기본적으로 int unsigned, bigint unsigned 사용 (int: 4바이트, 0 ~ 4,294,967,295 / bigint: 8바이트, 0 ~ 18,446,744,073,709,551,615)
  - 오더와 비례해서 증가하는 테이블의 경우와 데이터 증가치를 예상해서 많아질 경우 bigint unsigned 사용
  - 음수를 사용하지 않는 컬럼은 모두 unsigned로 설정하여 범위 확대
  - 복합 PK보다 단일 PK 권장

- **클러스터드 인덱스 특성**
  - MySQL의 PK는 클러스터드 인덱스로 데이터가 PK 순서로 정렬됨
  - 테이블 데이터가 PK 순서대로 정렬되어 순차 읽기 성능 우수
  - PK 기준 range scan 성능 우수
  - 모든 보조 인덱스는 PK를 포함하여 구성되므로 PK 크기가 작을수록 인덱스 성능 향상
  - PK 사이즈가 클수록 모든 보조 인덱스 크기가 증가하므로 가능한 작게 유지
  - **비순차적 엔트리 변경 영향**: UUID 같은 비순차적 키를 사용할 경우 페이지 나누기와 프래그멘테이션이 발생해 전반적인 저장소 활용처럼 작용
  - **버퍼 풀 상태 활용**: INFORMATION_SCHEMA.INNODB_BUFFER_PAGE 테이블을 통해 현재 버퍼 풀에 캐싱된 클러스터드 인덱스 컨디션 확인 가능

### 2.2 Secondary Index 설계

- **인덱스 명명 규칙**
  ```sql
  -- Unique 인덱스
  UK_[컬럼명]

  -- 일반 인덱스
  IDX_[컬럼명]

  -- 복합 인덱스 (언더스코어 제거)
  IDX_ORDERID_AGENTID
  ```

- **인덱스 생성 기준**
  - Cardinality 0.85 이상인 컬럼만 생성
    - Cardinality = distinct row count / total row count
  - 복합 인덱스는 Cardinality 높은 순으로 컬럼 배치
    - 예) a_col(0.9), b_col(0.85), c_col(0.02)
    - CREATE INDEX IDX_ACOL_BCOL_CCOL ON test (a_col, b_col, c_col)
  - 인덱스 생성이 필요한 경우:
    - WHERE 절에서 자주 사용되는 컬럼
    - JOIN 조건으로 자주 사용되는 컬럼
    - ORDER BY에서 자주 사용되는 컬럼
    - GROUP BY에서 자주 사용되는 컬럼

- **복합 인덱스 설계**
  - created_at과 같은 기간조회 컬럼은 인덱스 앞부분에 배치하지 않는 것이 좋음
    - 기간조회 컬럼이 인덱스 앞부분에 있으면 넓은 범위로 인해 인덱스 활용도 감소
    - 예) created_at > '2023-01-01' 조건은 지정한 시점 이후의 전체 레코드를 조회하므로 인덱스 효율 저하
    - 제한된 범위를 가진 필터 컬럼을 인덱스 앞부분에 배치하는 것이 효율적
  - 선택도가 높은 컬럼을 앞에 배치 (고유값 비율이 높은 컬럼)
  - 최대 3-4개 컬럼으로 제한

- **인덱스 개수 관리**
  - 테이블당 인덱스 개수는 5-6개 이하로 제한
    - 과도한 인덱스는 INSERT/UPDATE/DELETE 작업시 모든 인덱스 업데이트 필요
    - 인덱스가 10개 이상이면 성능 저하가 많이 발생되므로 DBA 협의 필요
  - 불필요한 인덱스 정기적 제거
  - 커버링 인덱스 활용 (쿼리에서 필요한 모든 컬럼을 포함하는 인덱스)

- **데이터 분포 기반 인덱스 설계**
  - **컬럼 선택도(Selectivity) 기반**: 선택도 = 고유값 수 / 전체 행 수
    ```sql
    SELECT COUNT(DISTINCT column_name) / COUNT(*) AS selectivity
    FROM table_name;
    ```
  - **쿼리 조건 타입 고려**: 등호 조건 → 높은 선택도 → 범위 조건 순으로 배치
  - **예외 사항**: 매우 선택적인 범위 조건은 인덱스 순서에서 높은 순위 고려
    ```sql
    -- 범위 조건 선택도 확인 예시
    SELECT COUNT(*) / (SELECT COUNT(*) FROM table_name) AS range_selectivity
    FROM table_name
    WHERE date_column >= 'YYYY-MM-DD';
    ```

- **인덱스 검증 및 유지관리**
  - **실행 계획 분석**: EXPLAIN 및 EXPLAIN ANALYZE를 활용해 인덱스 효과 검증
  - **정기적 통계 갱신**: `ANALYZE TABLE` 수행으로 최신 통계 유지
  - **미사용 인덱스 모니터링**: sys.schema_unused_indexes 참조

### 2.3 MySQL 8.0 향상된 인덱스 기능

- **Invisible Indexes**
  - 인덱스를 비활성화하지 않고 쿼리 옵티마이저가 사용하지 않게 설정
  - 인덱스 테스트에 유용: `ALTER TABLE table_name ALTER INDEX index_name INVISIBLE`

- **디스크쓰레딩 최적화**
  - 인덱스 생성 시 온라인 DDL 활용 (MySQL 8.0)
  - 인덱스 재구성 최적화: `ALGORITHM=INPLACE, LOCK=NONE`



## 3. 테이블 및 인덱스 최적화 체크리스트

### 3.1 테이블 설계 체크리스트

- [ ] 테이블명은 복수형을 사용하고 있는가? (orders, customers 등)
- [ ] 테이블에 적절한 Comment가 추가되었는가?
- [ ] 대용량/대량 트랜잭션 테이블인 경우 DBA와 협의했는가?
- [ ] Soft Delete 패턴이 필요한 경우 관련 컬럼이 추가되었는가?
- [ ] 파티셔닝이 필요한 테이블의 경우 전략이 수립되었는가?

### 3.2 인덱스 설계 체크리스트

- [ ] PK는 적절한 타입(int/bigint unsigned)으로 설계되었는가?
- [ ] 인덱스 명명 규칙이 준수되었는가? (UK_, IDX_ 접두어)
- [ ] 복합 인덱스의 컬럼 순서가 Cardinality를 고려하여 최적화되었는가?
- [ ] 테이블당 인덱스 개수가 5-6개 이하로 제한되었는가?
- [ ] 인덱스 크기와 쿼리 패턴이 고려되었는가?
- [ ] 모든 컬럼의 선택도(Selectivity)를 측정하여 확인했는가?
- [ ] 등호 조건 → 높은 선택도 → 범위 조건 순으로 컬럼을 배치했는가?
- [ ] 인덱스 적용 후 실행 계획(EXPLAIN)을 분석하여 개선 여부를 확인했는가?
- [ ] 인덱스 유지보수 비용(공간, 쿼리 작업 비율)을 고려했는가?
- [ ] 정기적인 인덱스 사용률 모니터링 및 통계 갱신 계획이 수립되었는가?

## 4. 자주 발생하는 문제 및 해결책

### 4.1 인덱스 관련 문제

1. **인덱스가 사용되지 않는 문제**
   - 원인: WHERE 조건에서 함수 사용, 암시적 형변환, 부적절한 인덱스 설계
   - 해결책: EXPLAIN 사용하여 실행 계획 확인, 인덱스 힌트 사용, WHERE 절에서 함수 사용 피하기

2. **인덱스 단편화**
   - 원인: 빈번한 데이터 변경, 대량 삭제 후 삽입
   - 해결책: 주기적인 인덱스 재구성 (`OPTIMIZE TABLE`)

### 4.2 테이블 성능 문제

1. **대용량 테이블 처리**
   - 원인: 테이블 크기 증가로 인한 I/O 부하 증가
   - 해결책: 파티셔닝, 아카이빙, 불필요 데이터 정리

2. **잠금 경합(Lock Contention)**
   - 원인: 동시 트랜잭션 증가, 부적절한 인덱스, 긴 트랜잭션
   - 해결책: 인덱스 최적화, 트랜잭션 분할, 잠금 수준 조정

## 5. 추가 고려사항

### 5.1 모니터링 및 튜닝

- **주요 모니터링 쿼리**
  ```sql
  -- 느린 쿼리 식별
  SELECT * FROM sys.statements_with_runtimes_in_95th_percentile;

  -- 미사용 인덱스 확인
  SELECT * FROM sys.schema_unused_indexes;

  -- 인덱스 사용 통계
  SELECT * FROM sys.schema_index_statistics;
  ```

- **정기적인 점검 항목**
  - 테이블 성장 추이 모니터링
  - 인덱스 활용도 분석
  - 쿼리 실행 계획 검토

### 5.2 백업 및 복구 전략

- **백업 방식**
  - 논리적 백업: mysqldump
  - 물리적 백업: Percona XtraBackup
  - Aurora: 자동 백업 및 백트래킹 기능 활용

- **백업 테이블 명명 규칙**
  - 백업 테이블명: `{테이블명}_bak_{YYYYMMDD}`
  - 예: `orders_bak_20260203`
  - `_bak_` 접미사로 백업 목적을 명확히 하고, 8자리 날짜로 연도 혼동을 방지

- **데이터 아카이빙 전략**
  - 오래된 데이터 정기 아카이빙
  - 아카이브 테이블 별도 관리
  - 필요시 데이터 복원 절차 마련