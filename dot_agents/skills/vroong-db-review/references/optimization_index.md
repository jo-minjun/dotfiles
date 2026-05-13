# Aurora MySQL 3.x 인덱스 최적화 가이드

Aurora MySQL 3.x(MySQL 8.0 기반) 환경에서 인덱스를 효율적으로 관리하고 최적화하는 방법을 설명합니다. 이 가이드는 운영 환경에 부하를 최소화하면서 인덱스 성능을 개선하는 실용적인 방법을 제공합니다.

## 목차

1. [인덱스 최적화의 중요성](#인덱스-최적화의-중요성)
2. [Aurora MySQL 3.x 인덱스 특성](#aurora-mysql-3x-인덱스-특성)
3. [중복 인덱스 식별 및 제거](#중복-인덱스-식별-및-제거)
4. [미사용 인덱스 식별](#미사용-인덱스-식별)
5. [인덱스 사용 효율성 분석](#인덱스-사용-효율성-분석)
6. [누락된 인덱스 식별](#누락된-인덱스-식별)
7. [인덱스 유지보수 전략](#인덱스-유지보수-전략)

## 인덱스 최적화의 중요성

데이터베이스 성능 최적화에 있어 인덱스는 핵심적인 역할을 합니다. 하지만 인덱스가 많다고 항상 좋은 것은 아닙니다. 중복되거나 사용되지 않는 인덱스는 다음과 같은 문제를 일으킬 수 있습니다:

- 불필요한 스토리지 공간 낭비
- INSERT, UPDATE, DELETE 작업 시 성능 저하
- 옵티마이저의 실행 계획 선택 복잡성 증가
- 백업 및 복구 시간 증가

따라서 적절한 인덱스 관리는 Aurora MySQL 데이터베이스의 성능과 안정성을 위해 필수적입니다.

## Aurora MySQL 3.x 인덱스 특성

Aurora MySQL 3.x는 MySQL 8.0을 기반으로 하며 다음과 같은 인덱스 관련 특성이 있습니다:

- 최대 64개의 보조 인덱스 지원 (테이블당)
- 인덱스당 최대 16개 컬럼 포함 가능
- 인덱스 키 길이 최대 3072바이트 (InnoDB 테이블)
- 인덱스 정렬(Descending Index) 지원
- 함수 기반 인덱스(Functional Index) 지원
- 보이지 않는 인덱스(Invisible Index) 기능 지원

Aurora MySQL만의 특별한 고려사항:
- Aurora 스토리지 아키텍처는 공유 스토리지 모델 사용
- 인덱스 생성 시 Writer 인스턴스에서만 수행
- Reader 인스턴스는 인덱스 변경 시 자동으로 동기화

## 중복 인덱스 식별 및 제거

### 중복 인덱스 유형

1. **완전 중복(Exact Duplicate)**: 인덱스 컬럼이 정확히 동일
   - 예: `KEY idx1(a, b)`와 `KEY idx2(a, b)`

2. **접두사 중복(Prefix Duplicate)**: 한 인덱스가 다른 인덱스의 접두사
   - 예: `KEY idx1(a, b, c)`와 `KEY idx2(a, b)`

3. **서브셋 중복(Subset Duplicate)**: 한 인덱스의 컬럼이 다른 인덱스에 포함
   - 예: `KEY idx1(a, b, c)`와 `KEY idx2(b, c)`

### 중복 인덱스 식별 쿼리

```sql
-- 동일 테이블에서 중복 가능성이 있는 인덱스 식별
SELECT 
    t.TABLE_SCHEMA AS 데이터베이스명,
    t.TABLE_NAME AS 테이블명,
    GROUP_CONCAT(DISTINCT 
        CONCAT(
            s.INDEX_NAME, ' (', 
            GROUP_CONCAT(s.COLUMN_NAME ORDER BY s.SEQ_IN_INDEX), 
            ')'
        ) 
    ORDER BY s.INDEX_NAME) AS 인덱스목록
FROM 
    information_schema.STATISTICS s
JOIN 
    information_schema.TABLES t
    ON s.TABLE_SCHEMA = t.TABLE_SCHEMA
    AND s.TABLE_NAME = t.TABLE_NAME
WHERE 
    t.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
GROUP BY 
    t.TABLE_SCHEMA, t.TABLE_NAME
HAVING 
    COUNT(DISTINCT s.INDEX_NAME) > 1
ORDER BY 
    t.TABLE_SCHEMA, t.TABLE_NAME;

-- 접두사 중복 인덱스 식별 (더 정교한 분석)
WITH index_columns AS (
    SELECT 
        TABLE_SCHEMA,
        TABLE_NAME,
        INDEX_NAME,
        GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns_list,
        COUNT(*) AS column_count
    FROM 
        information_schema.STATISTICS
    WHERE 
        TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    GROUP BY 
        TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
)
SELECT 
    a.TABLE_SCHEMA AS 데이터베이스명,
    a.TABLE_NAME AS 테이블명,
    a.INDEX_NAME AS 인덱스1,
    a.columns_list AS 인덱스1컬럼,
    b.INDEX_NAME AS 인덱스2,
    b.columns_list AS 인덱스2컬럼,
    '접두사 중복 가능성 있음' AS 중복유형
FROM 
    index_columns a
JOIN 
    index_columns b
    ON a.TABLE_SCHEMA = b.TABLE_SCHEMA
    AND a.TABLE_NAME = b.TABLE_NAME
    AND a.INDEX_NAME != b.INDEX_NAME
    AND (
        (a.columns_list LIKE CONCAT(b.columns_list, '%') AND a.column_count > b.column_count)
        OR 
        (b.columns_list LIKE CONCAT(a.columns_list, '%') AND b.column_count > a.column_count)
    )
ORDER BY 
    a.TABLE_SCHEMA, a.TABLE_NAME;
```

### 중복 인덱스 제거 시 고려사항

1. **외래 키 제약조건**: 외래 키를 지원하는 인덱스는 신중히 검토
2. **쿼리 패턴 확인**: 인덱스가 사용되는 쿼리 패턴을 반드시 확인
3. **복합 인덱스 활용**: 컬럼 순서가 중요하므로 쿼리 패턴에 따라 선택
4. **무중단 변경**: 인덱스 제거 시 `ALGORITHM=INPLACE, LOCK=NONE` 옵션 활용
   - 단, 다음과 같은 상황에서는 무중단 변경이 불가능할 수 있습니다:
     * 외래 키가 관련된 인덱스 변경 시 (`LOCK=SHARED` 필요할 수 있음)
     * 프라이머리 키 변경 시 (테이블 재구성 필요)
     * 매우 큰 테이블(수백 GB 이상)의 경우
     * 트랜잭션이 매우 많은 상황에서 메타데이터 잠금으로 인한 지연
     * Aurora 백트랙 기능 사용 중이거나 글로벌 데이터베이스 환경

5. **ALTER 작업 실행 계획 확인**:
   - MySQL 8.0/Aurora MySQL 3.x에서는 `EXPLAIN ALTER TABLE` 명령으로 작업 방식 미리 확인 가능

```sql
-- 인덱스 추가 작업의 실행 계획 확인
EXPLAIN ALTER TABLE orders ADD INDEX idx_customer_created (customer_id, created_at);

-- 결과 예시:
-- message: Adding index 'idx_customer_created' to table 'orders'
-- algorithm: INPLACE
-- lock: NONE
```

위 예시의 결과에서 `algorithm: INPLACE, lock: NONE`이 표시되면 무중단 변경이 가능하지만, `algorithm: COPY, lock: EXCLUSIVE`로 나오면 테이블 재구성이 필요한 작업으로 운영 시간 중 실행하기 어려운 작업입니다.

## 미사용 인덱스 식별

### 미사용 인덱스 식별 쿼리

```sql
-- sys 스키마를 활용한 미사용 인덱스 확인 (운영 부하 최소화)
SELECT 
    object_schema AS 데이터베이스,
    object_name AS 테이블명, 
    index_name AS 인덱스명,
    index_columns AS 인덱스컬럼,
    sys.format_bytes(sum_index_size) AS 인덱스크기
FROM 
    sys.schema_unused_indexes
ORDER BY 
    sum_index_size DESC;

-- 또는 performance_schema를 직접 조회하는 방법
SELECT 
    t.INDEX_NAME AS 인덱스명,
    t.TABLE_SCHEMA AS 데이터베이스명,
    t.TABLE_NAME AS 테이블명,
    s.COUNT_STAR AS 총사용횟수,
    s.COUNT_READ AS 읽기횟수,
    s.COUNT_WRITE AS 쓰기횟수,
    s.COUNT_FETCH AS 가져오기횟수
FROM 
    performance_schema.table_io_waits_summary_by_index_usage s
JOIN 
    information_schema.statistics t
    ON s.OBJECT_SCHEMA = t.TABLE_SCHEMA
    AND s.OBJECT_NAME = t.TABLE_NAME 
    AND s.INDEX_NAME = t.INDEX_NAME
WHERE 
    s.COUNT_STAR = 0
    AND t.INDEX_NAME IS NOT NULL
    AND t.TABLE_SCHEMA NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')
ORDER BY 
    t.TABLE_SCHEMA, t.TABLE_NAME;
```

### 미사용 인덱스 관리 전략

1. **보이지 않는 인덱스(Invisible Index)**: 제거 전 인덱스를 보이지 않게 설정하여 영향 테스트
   ```sql
   ALTER TABLE 테이블명 ALTER INDEX 인덱스명 INVISIBLE;
   ```

2. **한시적 모니터링**: Performance Schema 재설정 후 일정 기간(예: 1주일) 사용량 모니터링
   ```sql
   -- Performance Schema 재설정
   CALL sys.ps_truncate_all_tables(FALSE);
   
   -- 1주일 후 미사용 인덱스 확인
   SELECT * FROM sys.schema_unused_indexes;
   ```

3. **점진적 제거**: 중요도가 낮은 인덱스부터 순차적으로 제거하고 영향 평가

## 인덱스 사용 효율성 분석

### 많이 사용되는 인덱스 분석

```sql
-- 가장 많이 사용되는 인덱스 상위 20개
SELECT 
    object_schema AS 데이터베이스명,
    object_name AS 테이블명,
    index_name AS 인덱스명,
    count_star AS 총사용횟수,
    count_read AS 읽기횟수,
    count_write AS 쓰기횟수,
    count_fetch AS 가져오기횟수,
    sys.format_time(sum_timer_wait) AS 총대기시간
FROM 
    sys.schema_index_statistics
WHERE 
    count_star > 0
ORDER BY 
    sum_timer_wait DESC
LIMIT 20;
```

### 인덱스 선택성(Selectivity) 분석

인덱스의 선택성이 높을수록(중복이 적을수록) 해당 인덱스는 효율적입니다.

```sql
-- 인덱스별 선택성(selectivity) 분석
SELECT 
    t.TABLE_SCHEMA AS 데이터베이스명,
    t.TABLE_NAME AS 테이블명,
    s.INDEX_NAME AS 인덱스명,
    s.COLUMN_NAME AS 컬럼명,
    s.SEQ_IN_INDEX AS 인덱스내순서,
    s.CARDINALITY AS 카디널리티,
    t.TABLE_ROWS AS 총행수,
    CASE 
        WHEN t.TABLE_ROWS > 0 THEN ROUND((s.CARDINALITY / t.TABLE_ROWS) * 100, 2)
        ELSE 0 
    END AS 선택성비율
FROM 
    information_schema.STATISTICS s
JOIN 
    information_schema.TABLES t
    ON s.TABLE_SCHEMA = t.TABLE_SCHEMA
    AND s.TABLE_NAME = t.TABLE_NAME
WHERE 
    t.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND t.TABLE_ROWS > 0
ORDER BY 
    선택성비율 ASC, t.TABLE_SCHEMA, t.TABLE_NAME, s.INDEX_NAME, s.SEQ_IN_INDEX
LIMIT 20;
```

## 누락된 인덱스 식별

### 테이블 스캔이 많은 쿼리 식별

```sql
-- 테이블 스캔이 많은 쿼리 식별
SELECT 
    DIGEST_TEXT AS 쿼리패턴,
    COUNT_STAR AS 실행횟수,
    sys.format_time(SUM_TIMER_WAIT) AS 총실행시간,
    sys.format_time(AVG_TIMER_WAIT) AS 평균실행시간,
    SUM_NO_INDEX_USED AS 인덱스미사용횟수,
    SUM_NO_GOOD_INDEX_USED AS 효율적인인덱스미사용횟수
FROM 
    performance_schema.events_statements_summary_by_digest
WHERE 
    (SUM_NO_INDEX_USED > 0 OR SUM_NO_GOOD_INDEX_USED > 0)
    AND DIGEST_TEXT NOT LIKE 'SHOW%'
    AND COUNT_STAR > 10
ORDER BY 
    SUM_TIMER_WAIT DESC
LIMIT 10;
```

### Performance Insights 활용

AWS Performance Insights는 Aurora MySQL의 성능 상태를 시각화하고 분석하는 강력한 도구입니다.

1. **기본 사용법**:
   - AWS 콘솔 > RDS > 데이터베이스 > Performance Insights 선택
   - '상위 SQL' 탭에서 가장 부하가 높은 쿼리 확인

2. **인덱스 관련 대기 이벤트 분석**:
   - 'io/table/sql/handler' 대기 이벤트가 많은 쿼리 식별
   - 'handler_read_*' 지표 분석으로 테이블 스캔 쿼리 식별

### EXPLAIN 분석

식별된 문제 쿼리에 대해 EXPLAIN을 실행하여 인덱스 사용 여부 확인:

```sql
-- 실행 계획 확인
EXPLAIN SELECT * FROM orders WHERE status = 'PENDING' AND created_at > '2023-01-01';

-- JSON 형식으로 더 자세한 정보 확인
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE status = 'PENDING' AND created_at > '2023-01-01';
```

주의사항: EXPLAIN은 Reader 인스턴스에서 실행하여 운영 환경에 부하를 주지 않도록 합니다.

## 인덱스 유지보수 전략

### 1. 정기적인 인덱스 점검

Aurora MySQL 환경에서는 월 1회 정도 다음 점검을 수행하는 것이 좋습니다:

1. 미사용 인덱스 식별
2. 중복 인덱스 식별
3. 인덱스 사용 효율성 분석
4. 테이블 통계 업데이트 검토

### 2. 인덱스 변경 모범 사례

#### 무중단 인덱스 변경

Aurora MySQL 3.x에서는 다음과 같이 인덱스를 온라인으로 생성/삭제할 수 있습니다:

```sql
-- 인덱스 생성
ALTER TABLE orders 
ADD INDEX idx_status_date (status, created_at)
ALGORITHM=INPLACE, LOCK=NONE;

-- 인덱스 제거
ALTER TABLE orders 
DROP INDEX idx_status_date
ALGORITHM=INPLACE, LOCK=NONE;
```

#### 대용량 테이블 인덱스 변경 전략

대용량 테이블(수십 GB 이상)의 경우 다음 전략을 고려하세요:

1. **트래픽 낮은 시간대 활용**: 오전 2-4시 등 트래픽이 가장 낮은 시간 활용
2. **pt-online-schema-change 고려**: 대규모 변경 시 Percona Toolkit 도구 검토
3. **블루/그린 배포 활용**: 새로운 스키마로 복제 후 전환하는 방식 검토

### 3. Aurora 특화 인덱스 최적화 팁

1. **Reader 인스턴스 활용**: 
   - 인덱스 분석 작업은 Reader 인스턴스에서 수행
   - 성능 모니터링도 가능한 Reader에서 수행

2. **유지보수 자동화**:
   - 정기적인 인덱스 분석 보고서 자동화
   ```bash
   #!/bin/bash
   # 월간 인덱스 분석 보고서 생성
   REPORT_FILE="/tmp/index_report_$(date +%Y%m).txt"
   
   echo "# Aurora MySQL 인덱스 분석 보고서 $(date)" > $REPORT_FILE
   echo "## 1. 미사용 인덱스" >> $REPORT_FILE
   mysql -h$READER_HOST -u$USER -p$PASS -e "SELECT * FROM sys.schema_unused_indexes" >> $REPORT_FILE
   
   echo "## 2. 중복 가능성 있는 인덱스" >> $REPORT_FILE
   # [중복 인덱스 쿼리 실행]
   
   echo "## 3. 가장 많이 사용되는 인덱스" >> $REPORT_FILE
   # [인덱스 사용량 쿼리 실행]
   
   # 이메일로 보고서 전송
   mail -s "월간 인덱스 분석 보고서" dba@example.com < $REPORT_FILE
   ```

3. **성능 메트릭 통합 모니터링**:
   - CloudWatch + Performance Insights + 인덱스 분석 통합 대시보드 구성
   - 인덱스 변경 후 성능 변화 추적

### 4. 인덱스 설계 원칙

1. **복합 인덱스 컬럼 순서**:
   - 선택성이 높은 컬럼을 앞에 배치
   - WHERE 절에 자주 사용되는 컬럼을 앞에 배치
   - 정렬이나 그룹화에 사용되는 컬럼은 WHERE 절 컬럼 다음에 배치

2. **인덱스 크기 최적화**:
   - 필요한 경우 접두어 인덱스(prefix index) 활용
   ```sql
   CREATE INDEX idx_email ON users(email(20));
   ```
   - CHAR/VARCHAR 대신 INT 타입의 컬럼 우선 인덱싱

3. **인덱스 성능과 유지보수 비용 간 균형 유지**:
   - 테이블당 인덱스 개수는 실제 쿼리 패턴과 워크로드에 맞게 최소한으로 유지하는 것이 중요함
   - 인덱스가 많을수록 SELECT 성능은 향상될 수 있으나, INSERT/UPDATE/DELETE 작업의 성능 저하와 스토리지 비용 증가를 고려
   - 현재 Aurora MySQL 3.x는 테이블당 최대 64개의 보조 인덱스 지원하지만, 다수의 인덱스는 유지보수 부담 초래
   - 정기적인 인덱스 사용 분석을 통해 불필요한 인덱스 식별 및 제거
   - 인덱스 추가나 제거 전에 성능 측정 지표를 설정하고 변경 전후 비교 평가

4. **커버링 인덱스 활용**:
   - 자주 조회되는 컬럼을 인덱스에 포함시켜 인덱스만으로 쿼리 해결
   ```sql
   -- status로 조회하고 created_at도 자주 함께 조회하는 경우
   CREATE INDEX idx_status_created ON orders(status, created_at);
   ```

## 결론

Aurora MySQL 3.x에서의 인덱스 최적화는 운영 부하를 최소화하면서 성능을 극대화하기 위한 중요한 작업입니다. 이 가이드에서 제공하는 쿼리와 전략을 활용하여 정기적인 인덱스 관리를 수행하면 데이터베이스 성능을 지속적으로 향상시킬 수 있습니다.

추가로, Aurora MySQL은 지속적으로 발전하고 있으므로 AWS 공식 문서와 최신 모범 사례를 주기적으로 확인하는 것이 좋습니다.

## 참고 자료

- [AWS Aurora MySQL 문서](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraMySQL.html)
- [MySQL 8.0 인덱스 최적화 가이드](https://dev.mysql.com/doc/refman/8.0/en/optimization-indexes.html)
- [Aurora MySQL 성능 최적화 모범 사례](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.BestPractices.html)
