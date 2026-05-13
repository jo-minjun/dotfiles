# Aurora PostgreSQL 모니터링 쿼리 가이드

Aurora PostgreSQL 데이터베이스 환경에서 성능 모니터링 및 문제 진단을 위한 유용한 쿼리 모음입니다. 이 가이드는 운영 환경에서 사용할 수 있는 다양한 모니터링 쿼리를 제공합니다.

## 목차

1. [세션 모니터링](#1-세션-모니터링)
2. [락(Lock) 모니터링](#2-락lock-모니터링)
3. [인덱스 분석](#3-인덱스-분석)
4. [테이블 상태 확인](#4-테이블-상태-확인)
5. [쿼리 분석](#5-쿼리-분석)
6. [트랜잭션 모니터링](#6-트랜잭션-모니터링)
7. [VACUUM 모니터링](#7-vacuum-모니터링)
8. [인덱스 재구축 모니터링](#8-인덱스-재구축-모니터링)
9. [데이터베이스 크기 확인](#9-데이터베이스-크기-확인)
10. [복제 모니터링](#10-복제-모니터링)

## 1. 세션 모니터링

### 활성 세션 조회

```sql
-- 현재 활성 세션 조회
SELECT 
    pid AS 프로세스ID, 
    usename AS 사용자, 
    application_name AS 애플리케이션, 
    client_addr AS 클라이언트IP,
    state AS 상태, 
    wait_event_type AS 대기이벤트유형,
    wait_event AS 대기이벤트,
    query AS 쿼리문,
    now() - query_start AS 실행시간
FROM 
    pg_stat_activity
WHERE 
    state != 'idle'
ORDER BY 
    now() - query_start DESC;
```

### 장시간 실행 쿼리 확인

```sql
-- 30초 이상 실행 중인 쿼리 확인
SELECT 
    pid AS 프로세스ID,
    usename AS 사용자, 
    now() - query_start AS 실행시간,
    state AS 상태,
    query AS 쿼리문
FROM 
    pg_stat_activity
WHERE 
    state != 'idle'
    AND now() - query_start > interval '30 seconds'
ORDER BY 
    now() - query_start DESC;
```

### 휴면(Idle) 트랜잭션 확인

```sql
-- 휴면 상태의 트랜잭션 확인
SELECT 
    pid AS 프로세스ID, 
    usename AS 사용자,
    application_name AS 애플리케이션,
    client_addr AS 클라이언트IP,
    now() - xact_start AS 트랜잭션지속시간,
    now() - state_change AS 휴면상태지속시간,
    query AS 마지막쿼리
FROM 
    pg_stat_activity
WHERE 
    state = 'idle in transaction'
ORDER BY 
    xact_start;
```

## 2. 락(Lock) 모니터링

### 현재 락 상태 확인

```sql
-- 현재 락 상태 확인
SELECT 
    relation::regclass AS 테이블명,
    mode AS 락유형,
    CASE locktype
        WHEN 'relation' THEN '테이블'
        WHEN 'tuple' THEN '튜플'
        WHEN 'transactionid' THEN '트랜잭션'
        ELSE locktype
    END AS 락종류,
    a.pid AS 프로세스ID,
    pg_blocking_pids(a.pid) AS 블로킹프로세스IDs,
    now() - query_start AS 지속시간,
    a.query AS 쿼리문
FROM 
    pg_locks l
JOIN 
    pg_stat_activity a ON l.pid = a.pid
WHERE 
    relation IS NOT NULL 
    AND relation::regclass::text NOT LIKE 'pg_%'
    AND a.pid != pg_backend_pid()  -- 자신의 세션 제외
ORDER BY 
    relation::regclass::text, mode;
```

### 블로킹 락 확인

```sql
-- 블로킹/대기 락을 함께 확인하는 고급 쿼리
SELECT 
    blocked_locks.pid AS 블록된PID,
    blocked_activity.usename AS 블록된사용자,
    blocking_locks.pid AS 블로킹PID,
    blocking_activity.usename AS 블로킹사용자,
    blocked_activity.query AS 블록된쿼리,
    blocking_activity.query AS 블로킹쿼리,
    now() - blocked_activity.query_start AS 블록된시간
FROM 
    pg_catalog.pg_locks blocked_locks
JOIN 
    pg_catalog.pg_stat_activity blocked_activity ON blocked_locks.pid = blocked_activity.pid
JOIN 
    pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN 
    pg_catalog.pg_stat_activity blocking_activity ON blocking_locks.pid = blocking_activity.pid
WHERE 
    NOT blocked_locks.granted;
```

### 특정 테이블의 락 상태 확인

```sql
-- 특정 테이블의 락 상태 확인
SELECT 
    a.datname AS 데이터베이스,
    c.relname AS 테이블명,
    l.locktype AS 락종류,
    l.mode AS 락모드,
    l.granted AS 승인여부,
    a.usename AS 사용자,
    a.query AS 쿼리문,
    a.query_start AS 쿼리시작시간,
    now() - a.query_start AS 지속시간,
    a.pid AS 프로세스ID
FROM 
    pg_locks l
JOIN 
    pg_stat_activity a ON l.pid = a.pid
JOIN 
    pg_class c ON l.relation = c.oid
JOIN 
    pg_namespace n ON c.relnamespace = n.oid
WHERE 
    c.relname = '테이블명'  -- 여기에 확인할 테이블명 입력
ORDER BY 
    a.query_start;
```

## 3. 인덱스 분석

### 인덱스 사용량 및 크기 확인

```sql
-- 인덱스 크기 및 사용량 확인
SELECT
    s.schemaname AS 스키마명,
    s.relname AS 테이블명,
    s.indexrelname AS 인덱스명,
    pg_size_pretty(pg_relation_size(s.indexrelid)) AS 인덱스크기,
    s.idx_scan AS 스캔횟수,
    s.idx_tup_read AS 읽은튜플수,
    s.idx_tup_fetch AS 가져온튜플수,
    CASE WHEN s.idx_scan > 0 
         THEN round(s.idx_tup_read::numeric / s.idx_scan, 2) 
         ELSE 0 END AS 스캔당읽은튜플평균,
    CASE WHEN i.indisunique THEN '예' ELSE '아니오' END AS 유니크인덱스
FROM
    pg_stat_user_indexes s
JOIN
    pg_index i ON s.indexrelid = i.indexrelid
ORDER BY
    pg_relation_size(s.indexrelid) DESC;
```

### 사용되지 않는 인덱스 확인

```sql
-- 사용되지 않는 인덱스 확인
SELECT
    schemaname AS 스키마,
    relname AS 테이블명,
    indexrelname AS 인덱스명,
    idx_scan AS 스캔횟수,
    pg_size_pretty(pg_relation_size(indexrelid)) AS 인덱스크기,
    pg_size_pretty(pg_table_size(relid)) AS 테이블크기
FROM
    pg_stat_user_indexes
WHERE
    idx_scan = 0  -- 한 번도 사용되지 않음
    AND pg_relation_size(indexrelid) > 10485760  -- 10MB 이상
ORDER BY
    pg_relation_size(indexrelid) DESC;
```

### 단편화된 인덱스 확인 (pgstattuple 확장 필요)

```sql
-- pgstattuple 확장 설치 (관리자 권한 필요)
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- 특정 인덱스의 내부 통계 확인
SELECT * FROM pgstattuple('인덱스명');
```

## 4. 테이블 상태 확인

### 테이블 크기 및 통계 확인

```sql
-- 테이블 크기 및 통계 정보
SELECT
    schemaname AS 스키마,
    relname AS 테이블명,
    pg_size_pretty(pg_total_relation_size(relid)) AS 총크기,
    pg_size_pretty(pg_relation_size(relid)) AS 테이블크기,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS 인덱스크기,
    n_live_tup AS 활성튜플,
    n_dead_tup AS 데드튜플,
    round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 2) AS 데드튜플비율,
    last_vacuum AS 마지막VACUUM,
    last_autovacuum AS 마지막AUTOVACUUM
FROM
    pg_stat_user_tables
ORDER BY
    pg_total_relation_size(relid) DESC;
```

### 데드 튜플이 많은 테이블 확인

```sql
-- 데드 튜플이 많은 테이블 확인
SELECT
    schemaname AS 스키마,
    relname AS 테이블명,
    n_live_tup AS 활성튜플,
    n_dead_tup AS 데드튜플,
    round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 2) AS 데드튜플비율,
    last_vacuum AS 마지막VACUUM,
    last_autovacuum AS 마지막AUTOVACUUM
FROM
    pg_stat_user_tables
WHERE
    n_dead_tup > 10000
    n_dead_tup > 10000
ORDER BY
    n_dead_tup DESC;
```

## 5. 쿼리 분석

### 느린 쿼리 로그 설정 확인

```sql
-- 느린 쿼리 로그 설정 확인
SHOW log_min_duration_statement;
```

### 쿼리 실행 계획 분석

```sql
-- 쿼리 실행 계획 분석
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) 
SELECT * FROM 테이블명 WHERE 조건;
```

### pg_stat_statements로 쿼리 성능 통계 확인 (확장 필요)

```sql
-- pg_stat_statements 확장 설치 (필요시)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 가장 많은 실행 시간을 소비하는 쿼리
SELECT
    round(total_exec_time::numeric, 2) AS 총실행시간,
    calls AS 호출횟수,
    round(mean_exec_time::numeric, 2) AS 평균실행시간,
    round((100 * total_exec_time / sum(total_exec_time) OVER())::numeric, 2) AS 비율,
    query AS 쿼리
FROM
    pg_stat_statements
ORDER BY
    total_exec_time DESC
LIMIT 20;
```

## 6. 트랜잭션 모니터링

### 활성 트랜잭션 확인

```sql
-- 활성 트랜잭션 확인
SELECT 
    pid, 
    usename AS 사용자, 
    application_name AS 애플리케이션, 
    client_addr AS 클라이언트IP,
    state AS 상태, 
    now() - xact_start AS 트랜잭션지속시간,
    now() - query_start AS 쿼리지속시간,
    query AS 현재쿼리
FROM 
    pg_stat_activity
WHERE 
    state != 'idle' 
    AND xact_start IS NOT NULL
ORDER BY 
    xact_start;
```

### 트랜잭션 ID 소진 모니터링

```sql
-- 트랜잭션 ID 소진 모니터링
SELECT 
    datname, 
    age(datfrozenxid) AS 트랜잭션ID수명,
    current_setting('autovacuum_freeze_max_age') AS 최대허용수명
FROM 
    pg_database
ORDER BY 
    age(datfrozenxid) DESC;
```

## 7. VACUUM 모니터링

### VACUUM 진행 상황 확인

```sql
-- VACUUM 진행 상황 확인 (PostgreSQL 9.6 이상)
SELECT
    pid,
    datname AS 데이터베이스,
    relid::regclass AS 테이블,
    phase AS 단계,
    heap_blks_total AS 힙블록전체수,
    heap_blks_scanned AS 스캔된블록수,
    heap_blks_vacuumed AS 처리된블록수,
    CASE WHEN heap_blks_total = 0 THEN 0
         ELSE round(100.0 * heap_blks_scanned / heap_blks_total, 2)
    END AS 스캔진행률,
    CASE WHEN heap_blks_total = 0 THEN 0
         ELSE round(100.0 * heap_blks_vacuumed / heap_blks_total, 2)
    END AS 처리진행률
FROM
    pg_stat_progress_vacuum;
```

### 자동 VACUUM 설정 확인

```sql
-- 자동 VACUUM 설정 확인
SELECT 
    name AS 설정명, 
    setting AS 값, 
    unit AS 단위, 
    context AS 컨텍스트
FROM 
    pg_settings
WHERE 
    name LIKE '%autovacuum%' 
    OR name LIKE '%vacuum%';
```

## 8. 인덱스 재구축 모니터링

### 인덱스 생성/재구축 진행 상황 확인

```sql
-- 인덱스 생성 진행 상황 확인 (PostgreSQL 12 이상)
SELECT
    pid,
    datname AS 데이터베이스명,
    relid::regclass AS 테이블명,
    phase AS 단계,
    blocks_done AS 완료된블록,
    blocks_total AS 전체블록,
    CASE
        WHEN blocks_total = 0 OR blocks_total IS NULL THEN 0
        ELSE round((blocks_done * 100.0 / blocks_total), 2)
    END AS 진행률
FROM
    pg_stat_progress_create_index;
```

### WAL(Write-Ahead Log) 생성량 모니터링

```sql
-- WAL 생성량 확인
SELECT
    now() AS 현재시간,
    pg_current_wal_lsn() AS 현재위치,
    pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS 총생성량_바이트,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) AS 총생성량;
```

## 9. 데이터베이스 크기 확인

### 데이터베이스별 크기 확인

```sql
-- 데이터베이스별 크기
SELECT
    datname AS 데이터베이스명,
    pg_size_pretty(pg_database_size(datname)) AS 크기
FROM
    pg_database
ORDER BY
    pg_database_size(datname) DESC;
```

### 스키마별 크기 확인

```sql
-- 스키마별 크기
SELECT
    nspname AS 스키마명,
    pg_size_pretty(sum(pg_relation_size(c.oid))) AS 크기
FROM
    pg_class c
JOIN
    pg_namespace n ON c.relnamespace = n.oid
WHERE
    nspname NOT LIKE 'pg_%'
    AND nspname != 'information_schema'
GROUP BY
    nspname
ORDER BY
    sum(pg_relation_size(c.oid)) DESC;
```

### 가장 큰 테이블 확인

```sql
-- 가장 큰 테이블 확인
SELECT
    schemaname AS 스키마명,
    relname AS 테이블명,
    pg_size_pretty(pg_total_relation_size(relid)) AS 전체크기,
    pg_size_pretty(pg_relation_size(relid)) AS 테이블크기,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS 인덱스크기
FROM
    pg_stat_user_tables
ORDER BY
    pg_total_relation_size(relid) DESC
LIMIT 20;
```

## 10. 복제 모니터링

### 복제 상태 확인

```sql
-- 복제 상태 확인 (Aurora의 경우 다른 메트릭 사용 필요)
SELECT
    client_addr AS 클라이언트주소,
    usename AS 사용자,
    application_name AS 애플리케이션,
    state AS 상태,
    sync_state AS 동기화상태,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)) AS 전송지연크기,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, write_lsn)) AS 쓰기지연크기,
    pg_size_pretty(pg_wal_lsn_diff(write_lsn, flush_lsn)) AS 플러시지연크기,
    pg_size_pretty(pg_wal_lsn_diff(flush_lsn, replay_lsn)) AS 재생지연크기,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS 총지연크기
FROM
    pg_stat_replication;
```

### Aurora 특화 모니터링

Aurora PostgreSQL 특화 모니터링은 AWS CloudWatch 메트릭 및 Aurora 관련 정보 조회 쿼리를 활용해야 합니다. AWS 콘솔의 RDS > 모니터링 섹션에서 다음을 확인할 수 있습니다:

- CPUUtilization (CPU 사용률)
- FreeableMemory (사용 가능한 메모리)
- AuroraReplicaLag (복제 지연)
- ReadIOPS / WriteIOPS (읽기/쓰기 I/O 작업 수)
- VolumeReadIOPS / VolumeWriteIOPS (스토리지 I/O 작업 수)

## 참고사항

1. 모든 쿼리는 PostgreSQL 12 이상을 기준으로 작성되었습니다.
2. Aurora PostgreSQL 환경에서 일부 시스템 뷰가 다르게 구현될 수 있습니다.
3. 특정 확장 기능이 필요한 쿼리는 사용 전에 확장이 설치되어 있는지 확인하세요.
4. 운영 환경에서 복잡한 모니터링 쿼리를 실행할 때는 시스템 부하에 주의하세요.
