# Aurora MySQL 장애 대응 가이드

Aurora MySQL 3.x (MySQL 8.0) 환경에서 발생할 수 있는 다양한 장애 상황에 대한 진단 및 대응 가이드입니다. 이 문서는 운영 중 발생하는 긴급 상황에서 문제를 신속하게 진단하고 조치할 수 있는 참조 자료로 활용할 수 있습니다.

## 심각도 수준 및 가이드 활용 방법

이 가이드에서는 문제 상황의 심각도를 다음과 같이 분류합니다:

- 🟢 **정상**: 모니터링만 필요한 상태
- 🟡 **주의**: 지속적 관찰이 필요하며 예방 조치 고려
- 🟠 **경고**: 즉각적인 조사와 대응이 필요한 상태
- 🔴 **심각**: 즉시 모든 리소스를 동원하여 대응해야 하는 상태

각 진단 쿼리 결과에 대한 심각도 기준을 제공하므로, 결과값을 확인하고 해당하는 심각도에 따라 조치를 취하시기 바랍니다. 심각도가 높은 문제(🟠, 🔴)는 즉시 담당 DBA 또는 상위 관리자에게 에스컬레이션해야 합니다.

## 목차

1. [긴급 상황별 대응 가이드](#1-긴급-상황별-대응-가이드)
2. [실시간 진단 스크립트](#2-실시간-진단-스크립트)
3. [주요 문제 유형별 대응 방법](#3-주요-문제-유형별-대응-방법)

## 1. 긴급 상황별 대응 가이드

### 1.1 데이터베이스 연결 불가 또는 지연

**증상:**
- 애플리케이션에서 DB 연결이 불가능하거나 타임아웃 발생
- 연결 풀에서 새로운 연결을 얻는 시간이 지연됨
- 애플리케이션 로그에 `Connection timed out`, `Too many connections` 오류

**심각도 판단 기준:**
- 🟡 **주의**: DatabaseConnections > max_connections 의 80%
- 🟠 **경고**: DatabaseConnections > max_connections 의 90%
- 🔴 **심각**: ConnectionAttempts 메트릭이 증가하면서 connection 혼잡 발생

**즉시 조치:**
1. AWS 콘솔에서 CloudWatch 메트릭 확인:
   - `DatabaseConnections`: 현재 연결 수 (심각도 기준: max_connections 의 80% 이상 🟡, 90% 이상 🟠)
   - `ConnectionAttempts`: 연결 시도 횟수 (급증하는 패턴은 🔴)
   - `CPUUtilization`: CPU 사용률 (85% 이상이 5분 이상 지속시 🟠)
   
2. 보안 그룹 설정 확인:
   - Aurora MySQL의 보안 그룹 인바운드 규칙이 올바르게 설정되어 있는지 확인
   
3. 대체 엔드포인트 접속 시도:
   - 읽기/쓰기 엔드포인트로 접속 시도
   - 리더 인스턴스로 직접 접속 시도

4. 필요시 긴급 복구 명령:
```bash
# 긴급 상황에서 특정 애플리케이션 서버만 연결 허용 조치
aws ec2 authorize-security-group-ingress \
    --group-id [보안그룹ID] \
    --protocol tcp \
    --port 3306 \
    --cidr [긴급접속IP]/32
```

### 1.2 과도한 부하 또는 성능 저하

**증상:**
- 쿼리 응답 시간 급증 (ms 단위에서 초 단위로 증가)
- 타임아웃 오류 증가 (DB 쿼리 타임아웃 예외 발생)
- 애플리케이션 응답 속도 저하 (Latency 증가)
- CloudWatch에서 성능 관련 메트릭 증가

**심각도 판단 기준:**
- 🟡 **주의**: CPUUtilization > 50% (10분 이상 지속) / ReadLatency > 5ms / WriteLatency > 10ms / 일반 쿼리 지연 발생
- 🟠 **경고**: CPUUtilization > 70% (3분 이상 지속) / ReadLatency > 15ms / WriteLatency > 20ms / 신규 커넥션 지연 발생
- 🔴 **심각**: CPUUtilization > 80% (1분 이상 지속) / ReadLatency > 25ms / WriteLatency > 30ms / 쿼리 타임아웃 사례 발생

**즉시 조치:**
1. AWS CloudWatch 메트릭 확인:
   - `CPUUtilization`: 최근 1시간 추이 확인 (80% 이상 1분 지속시 🔴)
   - `FreeableMemory`: 가용 메모리 (100MB 미만시 🔴)
   - `ReadIOPS/WriteIOPS`: I/O 요청량 증가 패턴 확인
   - `ReadLatency/WriteLatency`: I/O 지연 확인 (15ms/20ms 이상시 🟠, 25ms/30ms 이상시 🔴)

2. 문제 쿼리 식별 (아래 [2.1 현재 실행 중인 쿼리 확인](#21-현재-실행-중인-쿼리-확인) 참조):
   - `TIME` 값이 60초 이상인 쿼리는 긴급 검토 필요 🟠
   - `STATE`가 'Sending data'로 오래 지속되는 쿼리는 심각한 성능 문제 🔴

3. 장시간 실행 쿼리 종료:
   - 긴급 상황에서는 아래 [2.2 실행 중인 쿼리 KILL 명령 생성](#22-실행-중인-쿼리-kill-명령-생성-amazon-rds-전용) 참조
   
3. 애플리케이션 부하 축소:
   - 배치 작업 일시 중지
   - 읽기 부하를 리더 인스턴스로 분산
   
4. 확장 고려:
   - 인스턴스 유형 업그레이드 검토
   - 리더 인스턴스 추가 검토

### 1.3 Aurora 네이티브 복제 지연

**증상:**
- CloudWatch에서 `AuroraReplicaLag` 증가
- 리더 인스턴스의 데이터가 최신 상태가 아님
- 애플리케이션에서 리더 인스턴스 조회 시 오래된 데이터 반환

**심각도 판단 기준:**
- 🟡 **주의**: AuroraReplicaLag > 100ms (0.1초)
- 🟠 **경고**: AuroraReplicaLag > 1,000ms (1초)
- 🔴 **심각**: AuroraReplicaLag > 10,000ms (10초)

**Aurora MySQL 복제 지연 특성:**
- Aurora는 일반 MySQL과 달리 스토리지 계층에서 복제가 이루어짐
- 리더 노드는 클러스터 볼륨의 동일한 데이터에 접근하지만 지연이 발생할 수 있음
- 클러스터 볼륨의 페이지 캐시와 내부 스토리지 지연에 의한 복제 지연 발생

**즉시 조치:**
1. Aurora 복제 지연 확인 (AuroraReplicaLag > 1,000ms일 때 🟠, > 10,000ms일 때 🔴):
```sql
# Aurora MySQL 특화 복제 상태 확인 (Aurora 전용)
# replica_lag_in_msec로 복제 지연을 정확하게 밀리초 단위로 확인 가능
SELECT 
    server_id, 
    IF(session_id = 'master_session_id', 'writer', 'reader') AS ROLE, 
    replica_lag_in_msec AS '복제지연(밀리초)',
    ROUND(replica_lag_in_msec/1000, 2) AS '복제지연(초)',
    oldest_read_view_trx_id, 
    oldest_read_view_lsn
FROM mysql.ro_replica_status;
```

2. CloudWatch 메트릭 확인:
   - `AuroraReplicaLag` - 리더 인스턴스의 복제 지연(초)
   - `AuroraReplicaLagMaximum` - 클러스터 내 최대 복제 지연(초)
   - `DBLoadCPU` - CPU 로드 확인 (고부하가 복제 지연 원인일 수 있음)

3. 복제 지연 해결 조치:
   - 리더 인스턴스에 과도한 쿼리 부하가 있는지 확인 후 부하 분산
   - 리더 인스턴스 클래스 스케일 업 검토
   - 필요시 리더 노드 재부팅 (지연이 지속적으로 증가하는 경우)

### 1.4 바이너리 로그(Binlog) 복제 오류 및 중단

**증상:**
- `SHOW REPLICA STATUS`에서 `Replica_IO_Running` 또는 `Replica_SQL_Running`이 'No'
- `Last_Errno` 값이 0이 아닌 경우 (오류 발생)
- `Seconds_Behind_Source` 값이 지속적으로 증가

**심각도 판단 기준:**
- 🟡 **주의**: Seconds_Behind_Source > 10초
- 🟠 **경고**: Seconds_Behind_Source > 60초 또는 복제 지연 지속적 증가
- 🔴 **심각**: Replica_IO_Running=No / Replica_SQL_Running=No / Last_Errno 값이 0이 아닌 경우

**즉시 조치:**
1. 바이너리 로그 복제 상태 확인:
```sql
# 복제 상태 상세 확인
SHOW REPLICA STATUS\G
```

**문제의 예시 및 해석:**

```
*************************** 1. row ***************************
             Replica_IO_State: Waiting for source to send event  # 정상 상태
                  Source_Host: aurora-xxxx-cluster.cluster-xxxxxx.region.rds.amazonaws.com
                  Source_User: rdsrepladmin
                  Source_Port: 3306
                Connect_Retry: 60
              Source_Log_File: mysql-bin-changelog.123456  # 원본 로그 파일명
          Read_Source_Log_Pos: 123456789  # 원본에서 읽은 위치
               Relay_Log_File: relaylog.123456
                Relay_Log_Pos: 123456789
        Relay_Source_Log_File: mysql-bin-changelog.123456
           Replica_IO_Running: Yes  # 'No'이면 IO 쓰레드 문제
          Replica_SQL_Running: Yes  # 'No'이면 SQL 쓰레드 문제
             Replicate_Do_DB: 
         Replicate_Ignore_DB: 
                   Last_Errno: 0  # 0이 아닌 값은 오류 발생
                   Last_Error:  # 오류 메시지가 있으면 문제
                 Skip_Counter: 0
          Exec_Source_Log_Pos: 123456789  # 실제 실행한 위치
              Relay_Log_Space: 123456789
              Until_Condition: None
                Until_Log_Pos: 0
         Source_SSL_Allowed: No
         Source_SSL_CA_File: 
         Source_SSL_CA_Path: 
            Source_SSL_Cert: 
          Source_SSL_Cipher: 
             Source_SSL_Key: 
      Seconds_Behind_Source: 1234  # 지연 시간(초) - 300 초 이상이면 심각
```

**중요한 문제 심각도 지표:**
- `Replica_IO_Running: No` - IO 쓰레드가 중지됨. 네트워크 또는 로그 위치 문제
- `Replica_SQL_Running: No` - SQL 쓰레드가 중지됨. 쿼리 오류 발생 가능성
- `Last_Errno: [0이 아닌 값]` - 오류 발생, Last_Error 확인 필요
- `Last_Error: [error message]` - 구체적인 복제 오류 내용
- `Seconds_Behind_Source: [1000 이상]` - 심각한 복제 지연

2. 바이너리 로그 활성화 및 상태 확인:
```sql
SHOW BINARY LOGS;
```

3. 복제 오류 분석 및 조치:
```sql
# 오류 건너뛰기 - 주의: 데이터 불일치를 초래할 수 있음!
CALL mysql.rds_skip_repl_error;

# 복제 재시작
CALL mysql.rds_start_replication;
```

**⚠️ `rds_skip_repl_error` 사용 시 주의사항:**
- 이 명령어는 데이터 불일치를 유발할 수 있으며, 마스터와 리더 인스턴스 간 데이터 불일치는 어플리케이션 로직 오류를 초래할 수 있습니다.
- 이 명령어는 오로지 다음 상황에서만 사용해야 합니다:
  1. 읽기 전용 리더에서만 사용 (쓰기 작업을 수행하는 마스터에서는 절대 사용 금지)
  2. 복제 오류가 일시적이거나 비크리티컬한 데이터에 대한 것임을 확신할 때
  3. 반드시 `Last_Error` 내용을 확인하고 오류 내용을 기록한 후 사용
     ```sql
     # 복제 오류 상세 확인
     SHOW REPLICA STATUS\G
     
     # 관련 이벤트 로그 확인
     SELECT event_time, user_host, argument FROM mysql.general_log 
     WHERE command_type = 'Query' AND argument LIKE '%/*ERROR*/%' 
     ORDER BY event_time DESC LIMIT 50;
     ```
     
     # 바이너리 로그 다운로드 (Aurora RDS)
     ```sql
     # 1. 바이너리 로그 목록 확인
     SHOW BINARY LOGS;
     
     # 2. RDS 피드백 로그에서 바이너리 로그 다운로드 허용
     CALL mysql.rds_set_configuration('binlog retention hours', 24); # 최대 168시간(7일)
     
     # 3. AWS CLI로 다운로드 (로컬 서버에서 실행)
     aws rds download-db-log-file-portion \
       --db-instance-identifier [RDS 인스턴스명] \
       --log-file-name binlog/mysql-bin-changelog.XXXXXX \
       --output text > /tmp/binlog_file.bin
     ```
  4. 복제 오류 스킵 후 데이터 일관성 확인을 반드시 수행

4. 긴급 리더 재생성 (복제 오류가 복구 불가능한 경우):
   - AWS 콘솔에서 리더 인스턴스 삭제 후 재생성
   - 복제 오류가 심각하고 스킵할 수 없는 경우 가장 안전한 해결 방법

## 2. 실시간 진단 스크립트

### 2.1 현재 실행 중인 쿼리 확인

```sql
-- 🔍 현재 실행 중인 쿼리 전체 확인
-- 이 명령은 현재 접속한 모든 세션의 상태를 확인합니다.

-- 심각도 판단 기준:
-- 🟡 주의: TIME > 60초 / Sleep 세션 > 100개 / 보류 Query 세션 > 30개
-- 🟠 경고: TIME > 300초 / Locked 상태의 쿼리 발견 / Sleep 세션 > 500개
-- 🔴 심각: TIME > 1800초(30분) / 불필요한 민감 정보 조회 쿼리 / DB 프로세스 처리 능력 한계 고갈

-- 주요 컬럼 설명:
--   ID      : MySQL 스레드 ID (KILL 명령 시 사용)
--   USER    : 접속 사용자 (동일 사용자가 너무 많은 접속은 서비스 계정 공유 의심)
--   HOST    : 클라이언트 IP:PORT (특정 IP에서 과도한 접속은 분산 불규칙 의심)
--   DB      : 현재 사용 중인 데이터베이스 (없으면 NULL)
--   COMMAND : 연결 상태 (아래 참고)
--   TIME    : 현재 상태가 유지된 시간 (초). 🟠 TIME이 긴 Query 또는 Locked는 심각한 문제 가능성
--   STATE   : 세부 처리 상태 (아래 참고)
--   INFO    : 실행 중인 쿼리 전체 (FULL 옵션으로 전체 표시됨)

-- ▶ 주요 COMMAND 값:
--   Sleep           : 연결만 유지된 상태. TIME이 길면 커넥션 누수 의심
--   Query           : 쿼리 실행 중 (중요)
--   Connect         : 연결 시도 중
--   Binlog Dump     : 복제 중 (Slave 접속)
--   Killed          : 종료 중
--   Daemon          : 내부 백그라운드 쓰레드 (무시 가능)

-- ▶ 주요 STATE 값:
--   Locked                      : 트랜잭션 락 대기 중
--   Sending data                : 클라이언트에 결과 전송 중 (TIME이 길면 IO 병목 가능성)
--   Opening tables              : 테이블 열기 (락 또는 메타 락 의심 가능)
--   statistics                  : 인덱스 통계 수집
--   Waiting for table metadata  : 메타 락 대기 중
--   Waiting for index lock      : 인덱스 수준의 락 대기
--   end / cleaning up           : 정리 작업 중
--   NULL                        : Sleep 상태 등 (실행 중 아님)

SHOW FULL PROCESSLIST;
```

### 2.2 실행 중인 쿼리 KILL 명령 생성 (Amazon RDS 전용)

```sql
-- 💨 실행 중인 쿼리에 대해 KILL 명령 생성 (Amazon RDS 전용)
-- RDS에서는 `KILL <ID>` 대신 `CALL mysql.rds_kill(<ID>)` 사용
SELECT
  CONCAT('CALL mysql.rds_kill(', a1.ID, ');') AS kill_sql,
  a1.*
FROM information_schema.PROCESSLIST a1
WHERE a1.COMMAND = 'Query'
ORDER BY a1.TIME DESC;
```

### 2.3 오래 실행 중인 트랜잭션 확인

**심각도 판단 기준:**
- 🟡 **주의**: 트랜잭션 지속 시간 > 60초 / Sleep 상태의 열린 트랜잭션 발견
- 🟠 **경고**: 트랜잭션 지속 시간 > 300초(5분) / trx_rows_modified 값이 많은 트랜잭션 
- 🔴 **심각**: 트랜잭션 지속 시간 > 1800초(30분) / 전체 트랜잭션 수 이상 증가

```sql
-- ⏱ 오래 실행 중인 트랜잭션 (기본 5초 이상, 필요시 WHERE 절에서 시간 조정)
SELECT trx_id AS '트랜잭션 ID',
       trx_state AS '상태',
       trx_started AS '시작 시간',
       NOW() AS '현재 시간',
       (UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(trx_started)) AS '지속 시간(초)',
       CASE 
         WHEN (UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(trx_started)) > 1800 THEN '🔴 심각' 
         WHEN (UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(trx_started)) > 300 THEN '🟠 경고' 
         WHEN (UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(trx_started)) > 60 THEN '🟡 주의' 
         ELSE '🟢 정상' 
       END AS '심각도',
       trx_wait_started AS '대기 시작 시간',
       trx_mysql_thread_id AS '스레드 ID',
       trx_rows_modified AS '변경행수',
       trx_query AS '쿼리'
FROM information_schema.innodb_trx
WHERE (UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(trx_started)) > 5
ORDER BY (UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(trx_started)) DESC;

-- 트랜잭션과 세션 정보를 함께 조회(상세 정보 포함)
-- 오래된 순서대로 정렬하여 오랫동안 열린 트랜잭션을 파악하기 좋음
SELECT 
    a.trx_id, 
    a.trx_state, 
    a.trx_started, 
    b.id,
    TIMESTAMPDIFF(SECOND, a.trx_started, NOW()) AS "트랜잭션 지속 시간(초)",
    a.trx_rows_modified AS "변경된 행 수", 
    b.USER AS "사용자", 
    b.host AS "호스트", 
    b.db AS "DB", 
    b.command AS "명령", 
    b.info AS "쿼리"
FROM information_schema.innodb_trx a
JOIN information_schema.processlist b ON a.trx_mysql_thread_id = b.id 
ORDER BY a.trx_started;
```

**활용 팁**: 둘 이상의 트랜잭션이 오랫동안 실행되고 있는 경우, 문제가 된 쿼리의 세션 ID를 확인한 후 `CALL mysql.rds_kill(<세션ID>);` 명령으로 해당 세션을 종료할 수 있습니다. 그러나 이 작업은 실행 중인 트랜잭션을 강제 종료하여 데이터 일관성 문제를 초래할 수 있으므로 매우 주의해야 합니다.

### 2.4 락 대기 중인 쿼리 확인

```sql
-- 🔒 락 대기 중인 트랜잭션 상세
SELECT 
    r.trx_id AS waiting_trx_id,
    r.trx_mysql_thread_id AS waiting_thread,
    r.trx_query AS waiting_query,
    TIMESTAMPDIFF(SECOND, r.trx_wait_started, CURRENT_TIMESTAMP) AS wait_duration_seconds,
    p.object_schema AS locked_db,
    p.object_name AS locked_table,
    b.trx_id AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_thread,
    b.trx_query AS blocking_query,
    TIMESTAMPDIFF(SECOND, b.trx_started, CURRENT_TIMESTAMP) AS blocking_duration_seconds
FROM information_schema.innodb_trx r
JOIN performance_schema.data_lock_waits w ON 
    CONCAT('TRX_ID ', r.trx_id) = w.requesting_engine_transaction_id
JOIN performance_schema.data_locks p ON 
    p.engine_lock_id = w.requesting_engine_lock_id
JOIN information_schema.innodb_trx b ON 
    CONCAT('TRX_ID ', b.trx_id) = w.blocking_engine_transaction_id
ORDER BY wait_duration_seconds DESC;
```

### 2.5 락 관계 분석 및 차단 트랜잭션 확인

```sql
-- 🔄 락 관계 분석 (차단하는 세션과 차단 받는 세션)
SELECT 
  a.trx_mysql_thread_id AS '대기 중인 스레드',
  b.trx_mysql_thread_id AS '차단하는 스레드',
  pl_wait.info AS '대기 중인 쿼리',
  pl_block.info AS '차단하는 쿼리',
  a.trx_id AS waiting_trx_id,
  TIMESTAMPDIFF(SECOND, a.trx_wait_started, NOW()) AS '대기 시간(초)',
  a.trx_started AS '대기 트랜잭션 시작 시간',
  b.trx_started AS '차단 트랜잭션 시작 시간'
FROM information_schema.innodb_trx a
JOIN performance_schema.data_lock_waits w 
  ON CONCAT('TRX_ID ', a.trx_id) = w.requesting_engine_transaction_id
JOIN information_schema.innodb_trx b 
  ON CONCAT('TRX_ID ', b.trx_id) = w.blocking_engine_transaction_id
JOIN information_schema.processlist pl_wait 
  ON pl_wait.id = a.trx_mysql_thread_id
JOIN information_schema.processlist pl_block 
  ON pl_block.id = b.trx_mysql_thread_id
WHERE a.trx_state = 'LOCK WAIT'
ORDER BY TIMESTAMPDIFF(SECOND, a.trx_wait_started, NOW()) DESC;
```

### 2.6 연결 상태 및 사용자별 세션 통계

```sql
-- 👥 사용자별 접속 상태 통계
SELECT 
  USER,
  COUNT(*) AS '세션 수',
  SUM(COMMAND = 'Sleep') AS '휴면 상태 수',
  SUM(COMMAND = 'Query') AS '쿼리 실행 수',
  MAX(TIME) AS '최장 실행 시간(초)'
FROM information_schema.processlist 
GROUP BY USER
ORDER BY COUNT(*) DESC;
```

### 2.7 트랜잭션 목록 및 세부 정보

```sql
-- 📋 활성 트랜잭션 목록 및 세부 정보
SELECT 
  trx_id AS '트랜잭션 ID',
  trx_state AS '상태',
  trx_started AS '시작 시간',
  CASE trx_state 
    WHEN 'RUNNING' THEN TIMESTAMPDIFF(SECOND, trx_started, NOW())
    WHEN 'LOCK WAIT' THEN TIMESTAMPDIFF(SECOND, trx_wait_started, NOW())
    ELSE 0 
  END AS '실행/대기 시간(초)',
  trx_rows_locked AS '락된 행 수',
  trx_rows_modified AS '수정된 행 수',
  trx_concurrency_tickets AS '동시성 티켓',
  trx_isolation_level AS '격리 수준',
  trx_mysql_thread_id AS '스레드 ID',
  trx_query AS '실행 쿼리'
FROM information_schema.innodb_trx
ORDER BY 
  CASE trx_state 
    WHEN 'RUNNING' THEN TIMESTAMPDIFF(SECOND, trx_started, NOW())
    WHEN 'LOCK WAIT' THEN TIMESTAMPDIFF(SECOND, trx_wait_started, NOW())
    ELSE 0 
  END DESC;
```

### 2.8 메타데이터 락 확인

```sql
-- 🔐 메타데이터 락 확인 (DDL 또는 스키마 변경 관련)
SELECT 
  p.id AS '스레드 ID',
  p.user AS '사용자',
  p.host AS '호스트',
  p.db AS '데이터베이스',
  p.command AS '명령',
  p.time AS '실행 시간(초)',
  p.state AS '상태',
  m.object_schema AS '스키마명',
  m.object_name AS '객체명',
  m.lock_type AS '락 타입',
  m.lock_duration AS '락 지속시간',
  p.info AS '실행 쿼리'
FROM performance_schema.metadata_locks m
JOIN information_schema.processlist p ON m.owner_thread_id = p.id
WHERE p.command != 'Sleep'
ORDER BY p.time DESC;
```

### 2.9 서버 재부팅 확인

```sql
-- 🔄 서버 재부팅 여부 및 가동 시간 확인
-- 예상치 못한 재부팅이 발생했는지 확인할 때 유용합니다.
SELECT
  VARIABLE_VALUE AS Uptime_seconds,
  CONCAT(FLOOR(VARIABLE_VALUE/86400), '일 ', 
         FLOOR((VARIABLE_VALUE%86400)/3600), '시간 ',
         FLOOR((VARIABLE_VALUE%3600)/60), '분 ', 
         VARIABLE_VALUE%60, '초') AS Uptime_formatted,
  NOW() AS "현재시간",
  NOW() - INTERVAL VARIABLE_VALUE SECOND AS "시작시간",
  DATEDIFF(NOW(), NOW() - INTERVAL VARIABLE_VALUE SECOND) AS "가동일수"
FROM performance_schema.session_status
WHERE VARIABLE_NAME = 'Uptime';

-- 서버 상태 일반 정보 확인 (버전, 연결 수 등)
SHOW GLOBAL STATUS LIKE 'Uptime%';
SHOW GLOBAL STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL VARIABLES LIKE 'version%';
```

**참고**: Aurora MySQL 인스턴스가 예상치 않게 재부팅되었거나 장애 조치(failover)가 발생했다면, `Uptime` 값이 최근 재부팅 이후 시간만 표시됩니다. 갑작스러운, 예상치 못한 재부팅은 다음 원인일 수 있습니다:

- 시스템 유지보수 (예약된 패치)
- 하드웨어 장애
- 메모리 부족 또는 높은 CPU 사용률로 인한 자동 페일오버
- 데이터베이스 파라미터 변경에 따른 재시작

## 3. 주요 문제 유형별 대응 방법

### 3.1 데드락(Deadlock) 발생 시

**심각도 판단 기준:**
- 🟡 **주의**: 데드락 분기당 1회 미만 / 특정 테이블에서만 발생
- 🟠 **경고**: 데드락 분기당 5회 미만 / 여러 테이블에서 발생 / 사용자 경험 영향
- 🔴 **심각**: 데드락 분기당 5회 이상 / 중요 업무 트랜잭션 영향 / 사용자 경험 지속적 저하

1. 최근 데드락 정보 확인:
```sql
-- 기본 데드락 정보 확인 (일반적인 정보 포함)
-- 데드락 발생 시점, 관련 쿼리, 테이블, 인덱스 등 정보 확인 가능
SHOW ENGINE INNODB STATUS\G
```

**`SHOW ENGINE INNODB STATUS` 출력에서 중점적으로 봐야 할 섹션:**

1. **LATEST DETECTED DEADLOCK** 섹션:
   - 가장 최근에 발생한 데드락 정보
   - 관련 트랜잭션 ID와 차단한 쿼리 내용 확인
   - 테이블, 행, 인덱스에 대한 락 정보
   - 데드락 시간과 시스템의 선택(로백된 트랜잭션)

2. **TRANSACTIONS** 섹션:
   - 현재 실행 중인 트랜잭션 목록
   - 각 트랜잭션의 상태, 시간, 락 상태 확인
   - `ROLLING BACK` 상태의 트랜잭션 확인

3. **SEMAPHORES** 섹션:
   - 락 경합과 대기 통계
   - 경합이 심한 경우 OS 레벨에서의 문제 파악 가능

4. **INSERT BUFFER AND ADAPTIVE HASH INDEX** 섹션:
   - 인서트 버퍼와 적응형 해시 인덱스 상태

```sql

-- 현재 락 상태 상세 조회 (MySQL 8.0 전용)
-- 어떤 락이 현재 활성화되어 있는지 상세히 확인
-- ENGINE_LOCK_ID, ENGINE_TRANSACTION_ID, THREAD_ID, OBJECT_NAME, INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS 등 정보 포함
SELECT * FROM performance_schema.data_locks;

-- 현재 실행 중인 트랜잭션 상세 조회
-- 트랜잭션 ID, 시작 시간, 상태, 세션 ID, 쿼리 등 정보 포함
SELECT * FROM INFORMATION_SCHEMA.INNODB_TRX;

-- 락 대기 관계 상세 조회
-- 어떤 락이 다른 어떤 락을 기다리고 있는지 확인
SELECT * FROM performance_schema.data_lock_waits;
```

2. 데드락 발생 패턴 분석:
   - 데드락에 관련된 테이블 및 인덱스 확인
   - 애플리케이션의 트랜잭션 패턴 검토
   
3. 개선 방안:
   - 트랜잭션 내 테이블 접근 순서 일관화
   - 트랜잭션 크기 축소
   - 자주 데드락이 발생하는 쿼리의 인덱스 추가

### 3.2 연결 풀 고갈

1. 연결 현황 파악:
```sql
-- 사용자 별 연결 수 확인
SELECT USER, HOST, COUNT(*) AS count 
FROM information_schema.processlist 
GROUP BY USER, HOST 
ORDER BY count DESC;

-- Sleep 상태 세션 중 오래된 순으로 확인
SELECT id, user, host, db, command, time, state, info 
FROM information_schema.processlist 
WHERE command = 'Sleep' 
ORDER BY time DESC;

-- 오래된 Sleep 세션(8분 이상) 조회 및 킬 명령 생성
-- time 값을 조정하여 기준 시간 변경 가능
SELECT 
    id, 
    user, 
    host, 
    db, 
    command, 
    time AS sec, 
    time/60 AS min, 
    state, 
    info, 
    CONCAT('CALL mysql.rds_kill(', id, ');') AS kill_command
FROM information_schema.processlist 
WHERE command = 'Sleep' AND time > 480
ORDER BY time DESC;
```

2. 연결 관련 변수 확인:
```sql
SHOW GLOBAL VARIABLES LIKE 'max_connections';
SHOW GLOBAL STATUS LIKE 'max_used_connections';
```

3. 개선 방안:
   - 애플리케이션 연결 풀 설정 조정 (maxActive, maxIdle 등)
   - 불필요한 장기 연결 식별 및 제거
   - 필요시 max_connections 조정 (파라미터 그룹 수정)

### 3.3 느린 쿼리로 인한 성능 저하

1. 느린 쿼리 로그 활성화 및 분석:
```sql
-- 파라미터 그룹에서 slow_query_log=1, long_query_time=1 설정
-- 로그 분석은 RDS 콘솔 > 로그 & 이벤트에서 가능
```

2. 문제 쿼리 실행 계획 분석:
```sql
EXPLAIN ANALYZE [문제 쿼리];
```

3. 개선 방안:
   - 인덱스 추가 또는 수정
   - 쿼리 재작성
   - 애플리케이션 레벨 캐싱 적용
   - 데이터 파티셔닝 검토

### 3.4 트랜잭션 누수(HLL) 진단 및 해결

**심각도 판단 기준:**
- 🟡 **주의**: Sleep 상태 열린 트랜잭션 > 10개 / 트랜잭션 지속 시간 > 300초(5분)
- 🟠 **경고**: Sleep 상태 열린 트랜잭션 > 50개 / 트랜잭션 지속 시간 > 1800초(30분)
- 🔴 **심각**: Sleep 상태 열린 트랜잭션 > 100개 / 트랜잭션 지속 시간 > 3600초(1시간) / 연결풀 고갈 발생

1. 오래 실행 중인 트랜잭션 참조 시작 시간 기준 파악:
```sql
-- 트랜잭션 시작 시간 순 정렬 (오래된 트랜잭션은 위에 배치)
SELECT 
    a.trx_id, 
    a.trx_state, 
    a.trx_started, 
    TIMESTAMPDIFF(SECOND, a.trx_started, NOW()) AS "트랜잭션 기간(초)",
    TIMESTAMPDIFF(MINUTE, a.trx_started, NOW()) AS "트랜잭션 기간(분)",
    CASE 
        WHEN TIMESTAMPDIFF(SECOND, a.trx_started, NOW()) > 3600 THEN '🔴 심각' 
        WHEN TIMESTAMPDIFF(SECOND, a.trx_started, NOW()) > 1800 THEN '🟠 경고' 
        WHEN TIMESTAMPDIFF(SECOND, a.trx_started, NOW()) > 300 THEN '🟡 주의' 
        ELSE '🟢 정상' 
    END AS "심각도",
    a.trx_rows_modified, 
    b.USER, 
    b.host, 
    b.db, 
    b.command
FROM information_schema.innodb_trx a, information_schema.processlist b 
WHERE a.trx_mysql_thread_id = b.id 
ORDER BY trx_started;
```

2. 트랜잭션 누수(HLL) 상세 진단:
```sql
-- 특정 트랜잭션의 SQL 히스토리 출력
-- 주의: performance_schema.events_statements_history는 기본적으로 스레드당 10개 정도의 최근 쿼리만 저장
-- 실제 트랜잭션의 쿼리가 누락된 경우도 있음
SELECT 
    ps.id AS processlist_id, 
    th.thread_id, 
    trx.trx_started, 
    trx.trx_isolation_level,
    esh.EVENT_ID, 
    esh.sql_text AS SQL_TEXT, 
    esh.RETURNED_SQLSTATE, 
    esh.MYSQL_ERRNO, 
    esh.MESSAGE_TEXT
FROM information_schema.innodb_trx trx
JOIN information_schema.processlist ps ON trx.trx_mysql_thread_id = ps.id
LEFT JOIN performance_schema.threads th ON th.processlist_id = trx.trx_mysql_thread_id
LEFT JOIN performance_schema.events_statements_history esh ON esh.thread_id = th.thread_id
WHERE ps.command = 'Sleep' AND trx.trx_state = 'RUNNING' 
  AND trx_id = [INSERT_TRANSACTION_ID_HERE]  -- 1번 쿼리에서 식별한 trx_id 입력
ORDER BY esh.EVENT_ID;
```

**해결 방법:**

1. Sleep 상태이면서 트랜잭션이 열려있는 세션은 안전하게 킬 할 수 있음:
```sql
CALL mysql.rds_kill([processlist_id]);
```

2. 주요 원인과 방지 방법:
   - Hibernate/JPA 트랜잭션 누수: `@Transactional` 설정 검토
   - 연결풀 설정 문제: 연결 반환 누락 확인 (`maxLifetime`, `testOnBorrow` 검토)
   - 메서드 호출에서 트랜잭션 문 누락 검토: `try-finally`에서 commit/rollback 확인

3. 애플리케이션 코드 개선:
   - 트랜잭션 범위 최소화
   - AOP, 인터셉터 등을 활용한 트랜잭션 완료 여부 감시



---

작성일: 2025-05-02  
최종 업데이트: 2025-05-28
