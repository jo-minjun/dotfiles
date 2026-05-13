# Aurora MySQL 3.x(MySQL 8.0) 모니터링 쿼리 가이드

Aurora MySQL 3.x(MySQL 8.0) 환경에서 데이터베이스 성능과 상태를 모니터링하기 위한 유용한 쿼리들을 정리했습니다.
이 가이드라인은 운영 환경의 영향을 최소화하면서 필요한 정보를 얻을 수 있는 쿼리들로 구성되어 있습니다.

## 목차
1. [인덱스 사용량 모니터링](#1-인덱스-사용량-모니터링)
2. [쿼리 성능 모니터링](#2-쿼리-성능-모니터링)
3. [테이블 상태 모니터링](#3-테이블-상태-모니터링)
4. [연결 및 세션 모니터링](#4-연결-및-세션-모니터링)
5. [InnoDB 상태 모니터링](#5-innodb-상태-모니터링)
6. [복제 상태 모니터링](#6-복제-상태-모니터링)
7. [리소스 사용량 모니터링](#7-리소스-사용량-모니터링)

## 1. 인덱스 사용량 모니터링

### 1.1 사용되지 않는 인덱스 찾기
```sql
-- 운영 부하가 적은 방식으로 사용되지 않는 인덱스 확인
SELECT 
    object_schema AS '데이터베이스',
    object_name AS '테이블', 
    index_name AS '인덱스',
    count_star AS '총 이벤트 수',
    count_read AS '읽기 이벤트 수',
    count_fetch AS '가져오기 수',
    count_insert AS '삽입 수',
    count_update AS '업데이트 수',
    count_delete AS '삭제 수'
FROM 
    performance_schema.table_io_waits_summary_by_index_usage
WHERE 
    index_name IS NOT NULL
    AND count_star = 0
    AND object_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')
ORDER BY 
    object_schema, 
    object_name;
```

### 1.2 인덱스 사용 효율성 분석
```sql
-- 인덱스 사용 효율성 분석 (가벼운 버전)
SELECT 
    table_schema AS '데이터베이스',
    table_name AS '테이블',
    index_name AS '인덱스',
    rows_selected AS '선택된 행 수',
    select_latency AS '선택 지연 시간',
    rows_inserted AS '삽입된 행 수',
    insert_latency AS '삽입 지연 시간',
    rows_updated AS '업데이트된 행 수',
    update_latency AS '업데이트 지연 시간',
    rows_deleted AS '삭제된 행 수',
    delete_latency AS '삭제 지연 시간'
FROM 
    sys.schema_index_statistics
WHERE 
    table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')
ORDER BY 
    select_latency DESC
LIMIT 25;
```

### 1.3 중복 인덱스 확인
```sql
-- 중복 인덱스 확인 (가벼운 부하)
SELECT 
    * 
FROM 
    sys.schema_redundant_indexes
LIMIT 100;
```

## 2. 쿼리 성능 모니터링

### 2.1 느린 쿼리 확인
```sql
-- 가장 느린 쿼리 상위 10개
SELECT 
    query AS '쿼리',
    db AS '데이터베이스',
    exec_count AS '실행 횟수',
    total_latency AS '총 지연 시간',
    avg_latency AS '평균 지연 시간',
    rows_sent_avg AS '평균 반환 행 수',
    rows_examined_avg AS '평균 검사 행 수',
    first_seen AS '최초 발견',
    last_seen AS '마지막 발견'
FROM 
    sys.statements_with_runtimes_in_95th_percentile
ORDER BY 
    avg_latency DESC
LIMIT 10;
```

### 2.2 쿼리 실행 빈도 및 지연 시간
```sql
-- 쿼리 실행 빈도 및 지연 시간
SELECT 
    SUBSTRING(digest_text, 1, 80) AS '다이제스트',
    count_star AS '총 실행 횟수',
    round(avg_timer_wait/1000000000, 2) AS '평균 지연(ms)',
    round(sum_timer_wait/1000000000, 2) AS '총 지연(ms)',
    sum_rows_sent AS '반환된 총 행 수',
    sum_rows_examined AS '검사된 총 행 수',
    first_seen AS '최초 발견',
    last_seen AS '마지막 발견'
FROM 
    performance_schema.events_statements_summary_by_digest
WHERE 
    digest_text NOT LIKE '%information_schema%'
    AND digest_text NOT LIKE '%performance_schema%'
    AND last_seen > DATE_SUB(NOW(), INTERVAL 1 DAY)
ORDER BY 
    sum_timer_wait DESC
LIMIT 20;
```

### 2.3 전체 테이블 스캔 쿼리
```sql
-- 전체 테이블 스캔 쿼리
SELECT 
    db AS '데이터베이스',
    query AS '쿼리',
    exec_count AS '실행 횟수',
    total_latency AS '총 지연 시간',
    no_index_used_count AS '인덱스 미사용 횟수',
    no_good_index_used_count AS '적절한 인덱스 미사용 횟수',
    rows_sent_avg AS '평균 반환 행 수',
    rows_examined_avg AS '평균 검사 행 수'
FROM 
    sys.statements_with_full_table_scans
ORDER BY 
    total_latency DESC
LIMIT 20;
```

## 3. 테이블 상태 모니터링

### 3.1 테이블 크기 정보
```sql
-- 데이터베이스별 테이블 크기 (상위 20개)
SELECT 
    table_schema AS '데이터베이스',
    table_name AS '테이블',
    table_rows AS '행 수',
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS '크기(MB)',
    ROUND(data_length / 1024 / 1024, 2) AS '데이터 크기(MB)',
    ROUND(index_length / 1024 / 1024, 2) AS '인덱스 크기(MB)',
    ROUND(data_free / 1024 / 1024, 2) AS '여유 공간(MB)'
FROM 
    information_schema.tables
WHERE 
    table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
ORDER BY 
    (data_length + index_length) DESC
LIMIT 20;
```

### 3.2 데이터베이스별 디스크 사용량
```sql
-- 데이터베이스별 디스크 사용량
SELECT 
    table_schema AS '데이터베이스',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS '총 크기(MB)'
FROM 
    information_schema.tables
GROUP BY 
    table_schema
ORDER BY 
    SUM(data_length + index_length) DESC;
```

### 3.3 테이블 자동 증가 값 상태
```sql
-- 테이블 자동 증가 값 상태 모니터링
SELECT 
    table_schema AS '데이터베이스',
    table_name AS '테이블',
    column_name AS '컬럼',
    data_type AS '데이터 타입',
    auto_increment AS '현재 자동 증가 값',
    max_value AS '최대 가능 값',
    ROUND((auto_increment / max_value) * 100, 2) AS '사용률(%)'
FROM 
    (
        SELECT 
            table_schema, 
            table_name, 
            column_name, 
            data_type,
            auto_increment,
            CASE 
                WHEN data_type = 'tinyint' THEN IF(column_type LIKE '%unsigned%', 255, 127)
                WHEN data_type = 'smallint' THEN IF(column_type LIKE '%unsigned%', 65535, 32767)
                WHEN data_type = 'mediumint' THEN IF(column_type LIKE '%unsigned%', 16777215, 8388607)
                WHEN data_type = 'int' THEN IF(column_type LIKE '%unsigned%', 4294967295, 2147483647)
                WHEN data_type = 'bigint' THEN IF(column_type LIKE '%unsigned%', 18446744073709551615, 9223372036854775807)
            END AS max_value
        FROM 
            information_schema.tables t
        JOIN 
            information_schema.columns c ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE 
            t.auto_increment IS NOT NULL
            AND c.extra LIKE '%auto_increment%'
            AND t.table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    ) AS ai_usage
WHERE 
    auto_increment / max_value > 0.5  -- 50% 이상 사용된 경우만 표시
ORDER BY 
    (auto_increment / max_value) DESC;
```

## 4. 연결 및 세션 모니터링

### 4.1 활성 세션 및 잠금 상태
```sql
-- 활성 세션 및 잠금 정보
SELECT 
    p.id AS '스레드 ID',
    p.user AS '사용자',
    p.host AS '호스트',
    SUBSTRING_INDEX(p.db, '/', 1) AS '데이터베이스',
    SUBSTRING(p.command, 1, 16) AS '명령',
    p.time AS '실행 시간(초)',
    p.state AS '상태',
    p.info AS '쿼리',
    IF(trx.trx_id IS NOT NULL, 'YES', 'NO') AS '트랜잭션 중',
    IF(trx.trx_state = 'LOCK WAIT', 'YES', 'NO') AS '락 대기',
    IF(l.requesting_trx_id IS NOT NULL, 'YES', 'NO') AS '락 요청 중'
FROM 
    information_schema.processlist p
LEFT JOIN 
    information_schema.innodb_trx trx ON p.id = trx.trx_mysql_thread_id
LEFT JOIN 
    information_schema.innodb_lock_waits l ON trx.trx_id = l.requesting_trx_id
WHERE 
    p.command != 'Sleep'
    AND p.time > 2
ORDER BY 
    p.time DESC
LIMIT 30;
```

### 4.2 연결 통계
```sql
-- 사용자별 연결 통계
SELECT 
    user AS '사용자',
    host AS '호스트',
    COUNT(*) AS '총 연결 수',
    SUM(IF(command = 'Sleep', 1, 0)) AS '휴면 연결 수',
    SUM(IF(command != 'Sleep', 1, 0)) AS '활성 연결 수'
FROM 
    information_schema.processlist
GROUP BY 
    user, 
    host
ORDER BY 
    COUNT(*) DESC;
```

### 4.3 장기 실행 세션
```sql
-- 1분 이상 실행 중인 쿼리
SELECT 
    id AS '스레드 ID',
    user AS '사용자',
    host AS '호스트',
    db AS '데이터베이스',
    command AS '명령',
    time AS '실행 시간(초)',
    state AS '상태',
    info AS '쿼리'
FROM 
    information_schema.processlist
WHERE 
    command != 'Sleep' 
    AND time > 60
ORDER BY 
    time DESC;
```

## 5. InnoDB 상태 모니터링

### 5.1 InnoDB 버퍼 풀 상태
```sql
-- InnoDB 버퍼 풀 상태
SELECT 
    FORMAT_BYTES(pool_size) AS '버퍼 풀 크기',
    FORMAT_BYTES(free_buffers * @@innodb_page_size) AS '여유 버퍼',
    FORMAT_BYTES(database_pages * @@innodb_page_size) AS '데이터베이스 페이지',
    ROUND((database_pages * 100) / (pool_size / @@innodb_page_size), 2) AS '버퍼 풀 사용률(%)',
    ROUND(read_requests / (read_requests + reads), 4) * 100 AS '버퍼 풀 히트율(%)'
FROM 
    performance_schema.memory_summary_global_by_event_name
JOIN 
    performance_schema.global_status
WHERE 
    event_name LIKE '%innodb_buffer_pool%'
    AND variable_name LIKE 'innodb_buffer_pool%pages%';
```

### 5.2 InnoDB 트랜잭션 및 락 상태
```sql
-- 장기 실행 트랜잭션 및 락 상태
SELECT 
    trx.trx_id AS '트랜잭션 ID',
    trx.trx_started AS '시작 시간',
    TIMESTAMPDIFF(SECOND, trx.trx_started, NOW()) AS '실행 시간(초)',
    trx.trx_mysql_thread_id AS '스레드 ID',
    PROCESSLIST.USER AS '사용자',
    PROCESSLIST.HOST AS '호스트',
    PROCESSLIST.DB AS '데이터베이스',
    trx.trx_state AS '트랜잭션 상태',
    trx.trx_weight AS '가중치',
    trx.trx_tables_in_use AS '사용 중인 테이블 수',
    trx.trx_tables_locked AS '잠긴 테이블 수',
    trx.trx_rows_locked AS '잠긴 행 수',
    trx.trx_rows_modified AS '수정된 행 수',
    PROCESSLIST.INFO AS '쿼리'
FROM 
    information_schema.innodb_trx trx
JOIN 
    information_schema.processlist PROCESSLIST ON trx.trx_mysql_thread_id = PROCESSLIST.ID
WHERE 
    TIMESTAMPDIFF(SECOND, trx.trx_started, NOW()) > 10
ORDER BY 
    trx.trx_started;
```

### 5.3 InnoDB 메타데이터 락
```sql
-- 메타데이터 락 정보
SELECT 
    *
FROM 
    performance_schema.metadata_locks
WHERE 
    owner_thread_id IN (
        SELECT 
            thread_id
        FROM 
            performance_schema.threads
        WHERE 
            processlist_id IN (
                SELECT 
                    id
                FROM 
                    information_schema.processlist
                WHERE 
                    command != 'Sleep'
                    AND time > 5
            )
    );
```

## 6. 복제 상태 모니터링

### 6.1 복제 상태 확인
```sql
-- 복제 상태 기본 정보
SHOW SLAVE STATUS\G
```

### 6.2 간략한 복제 상태
```sql
-- 간략한 복제 상태 정보
SELECT 
    VARIABLE_VALUE AS 'Slave_IO_State'
FROM 
    performance_schema.global_status 
WHERE 
    VARIABLE_NAME = 'Slave_IO_State';

SELECT 
    SUBSTRING_INDEX(VARIABLE_VALUE, ':', 1) AS 'Seconds_Behind_Master'
FROM 
    performance_schema.global_status 
WHERE 
    VARIABLE_NAME = 'Seconds_Behind_Master';
```

### 6.3 복제 지연 모니터링
```sql
-- 복제 지연 상세 정보
SELECT 
    CHANNEL_NAME AS '채널명',
    SERVICE_STATE AS '서비스 상태',
    LAST_APPLIED_TRANSACTION AS '마지막 적용 트랜잭션',
    LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP AS '원본 커밋 시간',
    LAST_APPLIED_TRANSACTION_IMMEDIATE_COMMIT_TIMESTAMP AS '즉시 커밋 시간',
    LAST_APPLIED_TRANSACTION_START_APPLY_TIMESTAMP AS '적용 시작 시간',
    LAST_APPLIED_TRANSACTION_END_APPLY_TIMESTAMP AS '적용 종료 시간',
    SOURCE_CONNECTION_AUTO_POSITION AS '자동 위치'
FROM 
    performance_schema.replication_applier_status_by_worker
LIMIT 1;
```

## 7. 리소스 사용량 모니터링

### 7.1 메모리 사용량
```sql
-- 글로벌 메모리 사용량 내역
SELECT 
    event_name AS '이벤트명',
    FORMAT_BYTES(current_alloc) AS '현재 할당량',
    FORMAT_BYTES(high_alloc) AS '최대 할당량'
FROM 
    sys.memory_global_by_current_bytes
WHERE 
    current_alloc > 0
ORDER BY 
    current_alloc DESC
LIMIT 10;
```

### 7.2 테이블별 I/O 통계
```sql
-- 테이블별 I/O 통계
SELECT 
    table_schema AS '데이터베이스',
    table_name AS '테이블',
    rows_fetched AS '가져온 행 수',
    fetch_latency AS '가져오기 지연 시간',
    rows_inserted AS '삽입된 행 수',
    insert_latency AS '삽입 지연 시간',
    rows_updated AS '갱신된 행 수',
    update_latency AS '갱신 지연 시간',
    rows_deleted AS '삭제된 행 수',
    delete_latency AS '삭제 지연 시간',
    io_read_requests AS '읽기 요청 수',
    io_read AS '읽기 양',
    io_read_latency AS '읽기 지연 시간',
    io_write_requests AS '쓰기 요청 수',
    io_write AS '쓰기 양',
    io_write_latency AS '쓰기 지연 시간'
FROM 
    sys.schema_table_statistics
WHERE 
    table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')
ORDER BY 
    (io_read_latency + io_write_latency) DESC
LIMIT 15;
```

### 7.3 I/O 대기 시간이 긴 파일
```sql
-- I/O 지연이 긴 파일 (데이터/인덱스 파일)
SELECT 
    file_name AS '파일명',
    total_io AS '총 I/O 횟수',
    total_io_latency AS '총 I/O 지연 시간',
    count_read AS '읽기 횟수',
    read_latency AS '읽기 지연 시간',
    count_write AS '쓰기 횟수',
    write_latency AS '쓰기 지연 시간',
    count_misc AS '기타 횟수',
    misc_latency AS '기타 지연 시간'
FROM 
    sys.io_global_by_file_by_latency
WHERE 
    file_name LIKE '%ibd%'
ORDER BY 
    total_io_latency DESC
LIMIT 15;
```

## 주의사항 및 권장사항

1. **운영 환경에서 주의사항**:
   - 위 쿼리들은 performance_schema와 sys 스키마를 사용하므로 이들이 활성화되어 있어야 합니다.
   - 운영 시간 중 무거운 쿼리 실행은 피하고, LIMIT 구문을 적절히 활용하세요.
   - `ANALYZE TABLE`과 같은 테이블 통계 갱신 명령어는 운영 시간 중 사용을 제한하세요.

2. **권장 모니터링 주기**:
   - 인덱스 사용량: 주 1회
   - 쿼리 성능: 일 1회
   - 테이블 상태: 주 1회
   - 세션 및 락: 시간당 1회
   - InnoDB 상태: 일 1회
   - 복제 상태: 시간당 1회
   - 리소스 사용량: 일 1회

3. **Aurora MySQL 특화 정보**:
   - Aurora는 자동으로 통계를 수집하므로 `ANALYZE TABLE` 사용은 최소화하세요.
   - 대량 데이터 작업은 배치 처리로 분할 수행하세요.
   - 인덱스 재구성 필요 시 기존 인덱스를 유지하며 새 인덱스를 생성한 후 전환하는 방식을 우선 고려하세요.

---
작성일: 2025-04-24
