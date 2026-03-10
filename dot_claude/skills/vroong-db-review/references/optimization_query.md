# Aurora MySQL 3.x 쿼리 최적화 가이드라인

> **참고**: 이 문서는 Aurora MySQL 3.x(MySQL 8.0 기반) 환경에서의 쿼리 최적화 가이드라인을 제공합니다. 테이블 및 인덱스 설계에 관한 추가 정보는 [design_table_index.md](design_table_index.md) 문서를 참고하십시오.

## 1. 실행 계획 분석 및 최적화

### 1.1 EXPLAIN 명령어 활용

- **기본 EXPLAIN 사용법**
  ```sql
  EXPLAIN SELECT * FROM orders WHERE customer_id = 1001;
  ```

- **EXPLAIN FORMAT=JSON 활용**
  - 더 상세한 실행 계획 정보 확인 가능
  ```sql
  EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE customer_id = 1001;
  ```

- **EXPLAIN ANALYZE 활용**
  - 실제 쿼리 실행 비용과 시간 정보 제공
  - **주의**: 운영 환경에서는 제한적으로 사용 (쿼리가 실제로 실행됨)
  ```sql
  EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 1001;
  ```

- **EXPLAIN FORMAT=JSON 활용**
  - 실행 계획의 더 상세한 정보 확인 가능
  - 테이블 파티션, 인덱스 사용 방식, 필터링 조건 등 세부 정보 제공
  ```sql
  EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE customer_id = 1001;
  ```

- **실행 계획 주요 지표 해석**

  - **id**: 실행 순서를 나타내는 고유 식별자 (동일한 값은 동시 실행)
  
  - **select_type**: 서브쿼리 관계를 표시
    - `SIMPLE`: 단순 조회(서브쿼리 없음)
    - `PRIMARY`: 외부 쿼리 블록(주 쿼리)
    - `SUBQUERY`: 일반 서브쿼리 
    - `DERIVED`: FROM 절의 서브쿼리(MySQL 8.0은 구체화 가능)
    - `UNION`: UNION 연산의 두 번째 이후 서브쿼리
    - `MATERIALIZED`: 구체화된 서브쿼리 (IN 절에서 활용되어 성능 향상)
  
  - **table**: 조회하는 테이블 이름
  
  - **partitions**: 사용되는 파티션 (파티션 프루닝이 적용된 경우 확인 가능)
  
  - **type**: 테이블 접근 방식
    - 일반적인 성능 순서(상황에 따라 달라질 수 있음):
      `system` > `const` > `eq_ref` > `ref` > `fulltext` > `ref_or_null` > `index_merge` > `unique_subquery` > `index_subquery` > `range` > `index` > `ALL`
    
    - `system`: 데이터가 없거나 1행만 있는 테이블 (최고 성능)
    - `const`: 유니크 인덱스나 PK로 정확히 1행 가능 (eq 조건)
    - `eq_ref`: JOIN 시 유니크 인덱스나 PK로 정확히 1행 매칭
    - `ref`: 일반 인덱스로 JOIN 시 여러 행 매칭 가능
    - `fulltext`: 전문 검색 인덱스 사용
    - `ref_or_null`: `ref`와 비슷하나 NULL 값도 처리
    - `index_merge`: 여러 인덱스를 조합하여 결과 생성 (경우에 따라 `range`보다 좋거나 나을 수 있음)
    - `unique_subquery`: IN 절 서브쿼리를 인덱스 조회로 대체
    - `index_subquery`: `unique_subquery`와 비슷하나 유니크하지 않은 인덱스 사용
    - `range`: 인덱스를 활용한 범위 검색 (>, <, BETWEEN, IN 등)
    - `index`: 전체 인덱스 스캔 (테이블 전체 스캔보다는 좋음)
    - `ALL`: 테이블 전체 스캔 (일반적으로 최저 성능, 가능하면 피해야 함)
    
    - **중요 고려사항**: 실제 성능은 다음 요소에 따라 크게 달라질 수 있음
      - 데이터 분포와 테이블 통계 정보
      - 데이터베이스 버퍼와 캐시 상태
      - 인덱스 선택성
      - 다른 테이블과의 관계
      - WHERE 절 조건의 복잡성
    
    - 가능하면 `system`, `const`, `eq_ref`, `ref`, `range` 중 하나를 목표로 하세요
  
  - **possible_keys**: MySQL이 사용 가능한 인덱스 목록
  
  - **key**: 실제로 사용한 인덱스 (이 값이 NULL이면 인덱스 사용 안함)
  
  - **key_len**: 사용된 인덱스 키의 길이 (짧을수록 효율적 검색 개선)
  
  - **ref**: 인덱스와 비교되는 값이나 상수
  
  - **rows**: 추정 데이터 행 수 (적을수록 좋음)
  
  - **filtered**: 인덱스를 통해 읽어들인 행 중 WHERE 절 조건을 만족하는 행의 비율(%)
    - 높은 값(100%에 가까울수록): 인덱스가 필터링을 잘 지원하고 추가 작업이 적음
    - 낮은 값: 인덱스로 읽어들인 후 많은 행이 추가로 필터링되버림
    - 중요 고려사항: 단순히 높은 값만이 좋은 것이 아니라, 전체 실행 계획과 함께 고려해야 함(예: 잘못된 인덱스를 사용해도 filtered가 100%일 수 있음)
  
  - **Extra**: 추가 정보
    - `Using index`: 커버링 인덱스 사용 (데이터 파일 접근 없이 인덱스만으로 쿼리 처리)
    - `Using where`: 인덱스로 가져온 행에 추가 필터링 적용
    - `Using temporary`: 임시 테이블 생성 (주로 ORDER BY, GROUP BY에서 발생)
    - `Using filesort`: 인덱스를 통한 정렬이 불가능하여 추가 정렬 작업 필요
    - `Using join buffer`: 조인 처리를 위한 메모리 버퍼 사용
    - `Using index condition`: 인덱스 컨디션 푸시다운 (ICP) 최적화 사용
    - `Using MRR`: 멀티 레인지 리드 (MRR) 최적화 사용
    - **중요**: `Using where`와 `Using index`가 함께 나타나면, 커버링 인덱스를 사용하여 테이블 접근 없이 데이터를 가져왔으나, 인덱스의 키 부분(B-트리 검색)으로 직접 필터링되지 않는 일부 조건이 추가 필터링으로 처리됨을 의미합니다. 예를 들어, (a,b,c) 복합 인덱스에서 `WHERE a=1 AND c='x'` 조건이 있을 때, a는 인덱스 키로 검색되지만 c는 추가 필터링됨

### 1.2 인덱스 특성 이해 및 관리

- **INVISIBLE 인덱스 활용**
  - 인덱스 추가/변경 시 영향도 테스트에 유용
  - INVISIBLE 상태의 인덱스는 유지보수 비용(DML 작업 시 업데이트)이 발생하지만 옵티마이저가 자동으로 사용하지 않음
  ```sql
  -- 인덱스를 INVISIBLE로 생성
  CREATE INDEX idx_test ON orders(customer_id) INVISIBLE;
  
  -- 기존 인덱스를 INVISIBLE로 변경
  ALTER TABLE orders ALTER INDEX idx_customer_id INVISIBLE;
  
  -- 특정 세션에서만 INVISIBLE 인덱스 사용 활성화
  SET SESSION optimizer_switch='use_invisible_indexes=on';
  
  -- 인덱스 가시성 확인
  SELECT INDEX_NAME, IS_VISIBLE 
  FROM INFORMATION_SCHEMA.STATISTICS 
  WHERE TABLE_NAME = 'orders'
  GROUP BY INDEX_NAME;
  ```

- **복합 인덱스 활용 패턴**
  - 인덱스 순서는 `=` 조건 먼저, 그 다음 범위 조건(`>`, `<`, `BETWEEN`) 컬럼
  - 인덱스 컬럼 활용은 왼쪽부터 순차적으로 이루어짐
  ```sql
  -- (customer_id, order_date) 복합 인덱스의 경우:
  
  -- 좋음: 두 컬럼 모두 인덱스 활용
  SELECT * FROM orders WHERE customer_id = 1001 AND order_date > '2023-01-01';
  
  -- 제한적: customer_id만 인덱스 활용, order_date는 필터링으로 처리
  SELECT * FROM orders WHERE customer_id > 1000 AND order_date = '2023-01-01';
  
  -- 나쁨: 첫 번째 컬럼 없이는 두 번째 컬럼만으로 인덱스 활용 불가
  SELECT * FROM orders WHERE order_date = '2023-01-01'; -- 인덱스 미사용
  ```

### 1.3 실행 계획 최적화

- **Using index (커버링 인덱스)**: 테이블 접근 없이 인덱스만으로 쿼리 해결
  ```sql
  -- 좋음: 인덱스에 모든 필요 컬럼이 포함됨
  SELECT order_id, customer_id FROM orders WHERE customer_id = 1001;
  
  -- IDX_customer_id(customer_id, order_id) 인덱스가 있는 경우 커버링 인덱스 활용
  ```

- **Using temporary, Using filesort 회피**
  - ORDER BY, GROUP BY에서 인덱스 활용 패턴 적용
  - 정렬 기준이 되는 컬럼에 인덱스 생성 고려

- **인덱스 병합 (Index Merge) 활용**
  ```sql
  -- 여러 인덱스를 함께 사용하는 경우
  SELECT * FROM orders WHERE customer_id = 1001 OR order_date = '2023-01-01';
  ```

- **NOT NULL 제약 조건 활용**
  - NULL 값을 허용하는 컬럼은 인덱스 효율이 낮아짐
  - 가능하면 NOT NULL 제약 조건을 추가하고 DEFAULT 값 사용

## 2. 쿼리 작성 모범 사례

### 2.1 WHERE 절 최적화

- **인덱스 컬럼과 상수 비교**
  - 인덱스 컬럼을 변형하지 않고 원래 형태로 사용
  ```sql
  -- 나쁨: 함수가 인덱스 컬럼에 적용됨
  SELECT * FROM orders WHERE YEAR(order_date) = 2023;
  
  -- 좋음: 인덱스를 효과적으로 활용
  SELECT * FROM orders WHERE order_date >= '2023-01-01' AND order_date < '2024-01-01';
  ```

- **LIKE 패턴 최적화**
  - 전방 일치 패턴만 인덱스 활용 가능
  ```sql
  -- 좋음: 인덱스 사용 가능
  SELECT * FROM customers WHERE name LIKE 'Kim%';
  
  -- 나쁨: 인덱스 활용 불가
  SELECT * FROM customers WHERE name LIKE '%Kim%';
  ```

- **IN 절 최적화**
  - 소량의 값은 IN 절 사용, 대량 값은 임시 테이블과 JOIN 고려
  ```sql
  -- 소량: IN 절 사용
  SELECT * FROM orders WHERE customer_id IN (1001, 1002, 1003);
  
  -- 대량: 임시 테이블과 JOIN
  CREATE TEMPORARY TABLE tmp_customers (customer_id INT PRIMARY KEY);
  INSERT INTO tmp_customers VALUES (1001), (1002), ... /* 많은 값 */;
  SELECT o.* FROM orders o JOIN tmp_customers t ON o.customer_id = t.customer_id;
  ```

### 2.2 JOIN 최적화

- **JOIN 순서 최적화**
  - 작은 테이블을 먼저 조인 (MySQL 8.0은 대부분 자동 최적화)
  - 필터링된 결과가 작은 테이블을 드라이빙 테이블로 사용

- **JOIN 컬럼에 인덱스 생성**
  - 양쪽 JOIN 컬럼 모두에 인덱스 생성 권장
  - 특히 드리븐 테이블(두 번째 테이블)의 조인 컬럼에 인덱스 필수

- **불필요한 컬럼 제외**
  - SELECT * 대신 필요한 컬럼만 명시
  - 특히 TEXT, BLOB 타입 컬럼 제외 시 성능 크게 향상

### 2.3 서브쿼리 최적화

- **상관 서브쿼리(Correlated Subquery) 개선**
  - 가능하면 JOIN으로 변환
  ```sql
  -- 나쁨: 상관 서브쿼리
  SELECT o.*, (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
  FROM orders o;
  
  -- 좋음: JOIN으로 변환
  SELECT o.*, COUNT(oi.id) AS item_count
  FROM orders o
  LEFT JOIN order_items oi ON o.id = oi.order_id
  GROUP BY o.id;
  ```

- **EXISTS vs IN**
  - 외부 테이블이 크고 서브쿼리 결과가 작을 때: IN 사용
  - 서브쿼리 결과가 크고 외부 테이블이 작을 때: EXISTS 사용

- **파생 테이블(Derived Table) 최적화**
  - MySQL 8.0의 구체화 기능(Materialization) 활용
  - 필요시 인덱스 힌트를 사용하여 최적화

## 3. 트랜잭션 및 잠금 최적화

### 3.1 트랜잭션 최적화

- **트랜잭션 길이 최소화**
  - 장시간 실행 트랜잭션 회피
  - 커넥션 풀 고갈 및 잠금 경합 방지를 위해 빠른 커밋

- **적절한 격리 수준 선택**
  - 기본값인 REPEATABLE READ 유지
  - 특수 상황에서만 READ COMMITTED 고려

- **읽기 전용 트랜잭션 명시**
  ```sql
  START TRANSACTION READ ONLY;
  SELECT * FROM orders WHERE customer_id = 1001;
  COMMIT;
  ```

### 3.2 잠금 최적화

- **UPDATE 쿼리 최적화**
  - PK나 유니크 인덱스로 행 지정 (행 잠금)
  - 범위 조건은 잠금 범위가 넓어짐 (가능한 좁게 설정)

- **Deadlock 방지**
  - 테이블 접근 순서 일관성 유지
  - 트랜잭션 내 복수 테이블 작업 시 테이블 이름 알파벳 순서로 접근
  - 트랜잭션 길이를 최소화하여 잠금 충돌 가능성 감소

## 4. 페이징 쿼리 최적화

### 4.1 LIMIT 최적화

- **인덱스 커버링과 LIMIT**
  ```sql
  -- 나쁨: 늦은 페이지 접근 시 성능 저하
  SELECT * FROM orders ORDER BY order_date DESC LIMIT 10000, 10;
  
  -- 좋음: 커버링 인덱스 활용
  SELECT id FROM orders ORDER BY order_date DESC LIMIT 10000, 10;
  SELECT * FROM orders WHERE id IN (SELECT id FROM ...);
  ```

- **키셋 페이지네이션(Keyset Pagination)**
  - **LIMIT OFFSET의 단점**:
    * 페이지 번호가 커질수록(OFFSET이 클수록) 데이터베이스 부하가 증가
    * 매번 전체 데이터를 스캔한 후 필요한 데이터만 반환하는 구조
    * 데이터가 추가/삭제되는 동적 환경에서 결과가 중복되거나 누락될 수 있음
    * 대용량 테이블에서 다음 페이지로 이동할때 매우 비효율적

  - **키셋 페이지네이션 방식 예시**:
  ```sql
  -- 첫 페이지
  SELECT * FROM orders WHERE status = 'PENDING'
  ORDER BY created_at DESC LIMIT 10;
  
  -- 다음 페이지 (마지막 행의 created_at 값이 '2023-01-15 10:30:00'인 경우)
  SELECT * FROM orders 
  WHERE status = 'PENDING' AND created_at < '2023-01-15 10:30:00'
  ORDER BY created_at DESC LIMIT 10;
  ```

### 4.2 복잡한 정렬 최적화

- **복합 인덱스 활용**
  - ORDER BY와 WHERE 절이 일치하는 복합 인덱스 생성
  ```sql
  -- 인덱스: IDX_status_created_at(status, created_at)
  SELECT * FROM orders 
  WHERE status = 'PENDING' 
  ORDER BY created_at DESC;
  ```

## 5. 성능 튜닝 프로세스

### 5.1 쿼리 성능 문제 식별

- **느린 쿼리 로그 분석**
  - slow_query_log 활성화 및 주기적 분석
  - 기준 시간(long_query_time) 초과 쿼리 식별

### 5.2 쿼리 프로파일링

- **Aurora MySQL 3.x에서의 프로파일링 권장 순서**
  1. **낮은 부하 방식 먼저 시도**: performance_schema > profiling > EXPLAIN ANALYZE
  2. **운영 환경 고려사항**: 실제 쿼리 실행이 필요한 방식은 낮은 트래픽 시간대에 제한적으로 사용
  3. **인덱스 테스트**: INVISIBLE 인덱스와 `optimizer_switch` 설정으로 안전하게 테스트

- **성능 스키마(Performance Schema) 활용**
  - MySQL 8.0에서 권장되는 프로파일링 방법
  - performance_schema 활성화 및 설정
  ```sql
  -- 성능 스키마 활성화 확인
  SELECT @@performance_schema;
  
  -- 문장 이벤트 모니터링 활성화
  UPDATE performance_schema.setup_consumers
  SET ENABLED = 'YES'
  WHERE NAME LIKE '%statements%';
  ```

- **쿼리 다이제스트 분석**
  - 유사한 패턴의 쿼리를 그룹화하여 성능 분석
  ```sql
  -- 가장 많이 실행된 쿼리 패턴 파악
  SELECT DIGEST_TEXT, COUNT_STAR, SUM_TIMER_WAIT/1000000000 as SUM_TIMER_WAIT_MS,
         AVG_TIMER_WAIT/1000000000 as AVG_TIMER_WAIT_MS
  FROM performance_schema.events_statements_summary_by_digest
  ORDER BY SUM_TIMER_WAIT DESC
  LIMIT 10;
  ```

- **쿼리 실행 시간 상세 분석**
  - 쿼리의 각 단계별 소요 시간 분석
  ```sql
  -- 특정 쿼리의 실행 단계별 시간 분석
  SELECT EVENT_NAME, SOURCE, TIMER_WAIT/1000000000 as TIMER_WAIT_MS
  FROM performance_schema.events_stages_history_long
  WHERE NESTING_EVENT_ID = (
    SELECT EVENT_ID FROM performance_schema.events_statements_history
    WHERE SQL_TEXT LIKE '%your_query_pattern%'
    ORDER BY END_EVENT_ID DESC LIMIT 1
  );
  ```

- **시스템 변수 프로파일링 설정**
  ```sql
  -- 세션 레벨 프로파일링 활성화
  SET profiling = 1;
  
  -- 쿼리 실행
  SELECT * FROM orders WHERE customer_id = 1001;
  
  -- 프로파일링 결과 확인
  SHOW PROFILES;
  
  -- 특정 쿼리의 상세 프로파일 확인
  SHOW PROFILE FOR QUERY 1;
  SHOW PROFILE CPU, MEMORY, BLOCK IO FOR QUERY 1;
  ```
  
  - **SHOW PROFILE FOR QUERY 1 출력 항목 설명**
    | 상태 | 의미 | 성능 고려사항 |
    |------|------|----------------|
    | Starting | 쿼리 시작 | 일반적으로 짧은 시간 소요 |
    | checking permissions | 권한 확인 | 복잡한 권한 구조에서 오래 걸릴 수 있음 |
    | Opening tables | 테이블 오픈 | 테이블 캐시가 부족하면 길어질 수 있음 |
    | System lock | 시스템 락 획득 | 락 경합이 있으면 길어질 수 있음 |
    | init | 초기화 | 일반적으로 짧은 시간 소요 |
    | optimizing | 쿼리 최적화 | 복잡한 쿼리에서 길어질 수 있음 |
    | statistics | 통계 정보 수집 | 통계 정보가 오래되었거나 없으면 길어질 수 있음 |
    | preparing | 실행 준비 | 복잡한 쿼리에서 길어질 수 있음 |
    | Sending data | 데이터 가져오기/전송 | 가장 오래 걸리는 단계, 테이블 스캔 의심 |
    | end | 실행 종료 | 일반적으로 짧은 시간 소요 |
    | query end | 쿼리 종료 전 정리 작업 | 트리거나 저장 프로시저가 있으면 길어질 수 있음 |
    | freeing items | 메모리 해제 | 일반적으로 짧은 시간 소요 |
    | closing tables | 테이블 닫기 | 많은 테이블 사용시 길어질 수 있음 |
    | removing tmp table | 임시 테이블 제거 | 임시 테이블 사용시 길어질 수 있음, 큰 임시 테이블을 만들었다면 성능 문제 |
    | Creating sort index | 정렬 인덱스 생성 | ORDER BY, GROUP BY 사용시 길어질 수 있음 |
    | executing | 쿼리 실행 | 실제 데이터 처리 단계, 가장 많은 시간이 소요됨 |
    | Copying to tmp table | 임시 테이블 복사 | 대용량 임시 테이블 생성 시 오래 걸림 |
    | Sorting result | 결과 정렬 | 대용량 결과 집합 정렬 시 시간 소요 |
    | waiting for handler commit | 핸들러 커밋 대기 | 트랜잭션 커밋 지연 의심 |
  
  - **프로파일링 분석 후 주요 체크포인트**
    - **Sending data/executing** 단계가 전체 시간의 50% 이상 차지: 테이블 스캔 또는 비효율적 인덱스 사용 의심
    - **Creating sort index** 시간이 길면: ORDER BY/GROUP BY의 인덱스 활용 불가 의심
    - **statistics**, **preparing** 가 길면: 테이블 통계가 오래되었거나 복잡한 조인 방식 의심
    - **removing tmp table** 이 길면: 임시 테이블이 디스크에 저장되었을 가능성, 메모리 사용량 조정 필요
    - **Context_voluntary** 값이 높으면: I/O 대기 또는 잠금 대기 상황 발생
    - **Page_faults_major** 값이 높으면: 물리적 디스크 I/O 과다 발생
    - **Block_ops_in/out** 값이 높으면: 디스크 I/O 작업 과다, 임시 테이블이 디스크에 기록됨
  
  **참고**: `profiling` 변수는 향후 버전에서 제거될 예정이므로 성능 스키마 사용을 권장

- **Aurora MySQL 특화 성능 분석**
  - Aurora 인사이트 및 Performance Insights 활용
  ```sql
  -- Aurora 스토리지 엔진 상태 확인
  SHOW GLOBAL STATUS LIKE 'Aurora%';
  
  -- 볼륨 상태 확인
  SELECT * FROM information_schema.INNODB_METRICS
  WHERE NAME LIKE 'aurora%';
  ```

- **쿼리 프로파일링 결과 해석**
  - **주요 체크 포인트**:
    - 전체 실행 시간의 80% 이상을 차지하는 단계 식별
    - 테이블 풀 스캔 여부 확인
    - 임시 테이블 생성 및 디스크 사용 여부
    - 서브쿼리 및 JOIN 구문의 효율성
    - 락 대기 시간
  
  - **개선 지표**:
    - 실행 시간 50% 이상 단축
    - 디스크 I/O 감소
    - 임시 테이블 사용 제거
    - 인덱스 사용률 증가

- **쿼리 패턴 분석**
  - 반복 실행되는 고비용 쿼리 식별
  - 실행 계획 변동 쿼리 모니터링

### 5.2 쿼리 최적화 접근법

1. **기본 정보 수집**
   - EXPLAIN 분석으로 현재 실행 계획 파악
   - SHOW CREATE TABLE로 인덱스 구조 확인
   - 쿼리 패턴 및 데이터 분포 분석

2. **인덱스 최적화**
   - WHERE, JOIN, ORDER BY, GROUP BY 절 분석
   - 필요한 인덱스 추가 또는 불필요한 인덱스 제거
   - 복합 인덱스 컬럼 순서 최적화 (= 조건 먼저, 범위 조건 나중에)
   - 인덱스 변경 테스트는 INVISIBLE 상태에서 `optimizer_switch` 설정으로 안전하게 진행

3. **쿼리 재작성**
   - 서브쿼리를 JOIN으로 변환
   - 인덱스 친화적인 조건으로 재구성
   - 필요 없는 컬럼과 조인 제거

4. **스키마 재정비 검토**
   - 성능 문제가 지속적으로 발생하는 테이블 구조 분석
   - 테이블 정규화/비정규화 전략 검토
   - 대용량 테이블(100GB 이상)의 파티션 전략 검토
   - **운영 영향도 고려사항**:
     * 스키마 변경은 오프 피크 시간에 계획
     * 무중단 변경 도구(gh-ost, pt-online-schema-change) 활용
     * 사전 테스트 환경에서 영향도 검증 필수
     * ANALYZE TABLE과 같은 통계 갱신 명령은 운영 시간 중 사용 제한 (Aurora MySQL 3.x의 자동 통계 수집 활용)

5. **결과 검증**
   - 최적화 전후 성능 비교 (실행 시간, 리소스 사용량)
   - 다양한 데이터 볼륨에서 테스트

6. **모니터링 및 재평가**
   - 주기적인 성능 모니터링
   - 데이터 증가에 따른 성능 변화 관찰
   - 데이터베이스 성능 인사이트 툴 활용

## 6. 참고 자료

- [MySQL 8.0 Reference Manual - Optimization](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [Amazon Aurora MySQL 참조 가이드](https://docs.aws.amazon.com/ko_kr/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraMySQL.html)
- [테이블 및 인덱스 설계 가이드라인](design_table_index.md)
- [컬럼 설계 가이드라인](design_column.md)