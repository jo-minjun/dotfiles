# 데이터베이스 성능 최적화 가이드

## 1. Aurora MySQL 3.x 트랜잭션 관리와 격리 수준

### 1.1 트랜잭션 격리 수준의 이해

Aurora MySQL 3.x는 MySQL 8.0을 기반으로 하며 다음과 같은 트랜잭션 격리 수준을 지원합니다:

| 격리 수준 | 더티 리드 방지 | 비반복 읽기 방지 | 팬텀 리드 방지 |
|-----------|---------------|-----------------|--------------|
| READ UNCOMMITTED | ❌ | ❌ | ❌ |
| READ COMMITTED | ✅ | ❌ | ❌ |
| REPEATABLE READ (기본값) | ✅ | ✅ | ❌ |
| SERIALIZABLE | ✅ | ✅ | ✅ |

MySQL의 기본 격리 수준은 `REPEATABLE READ`이며, 이는 트랜잭션 내에서 동일한 SELECT 쿼리를 여러 번 실행해도 항상 동일한 결과를 보장합니다.

### 1.2 각 격리 수준의 성능 영향

격리 수준이 높을수록 데이터 일관성은 향상되지만 성능은 저하될 수 있습니다:

- **READ UNCOMMITTED**: 성능은 가장 좋지만 데이터 일관성이 보장되지 않아 프로덕션 환경에서는 권장되지 않음
- **READ COMMITTED**: 적절한 데이터 일관성과 성능 균형, OLTP 워크로드에 적합
- **REPEATABLE READ**: MySQL의 기본값, MVCC를 통해 적절한 성능 제공
- **SERIALIZABLE**: 가장 엄격한 격리 수준으로 성능 영향이 가장 큼

### 1.3 Aurora MySQL에서 트랜잭션 관리 최적화

- 트랜잭션은 가능한 짧게 유지하여 락 경합 최소화
- 대량의 데이터를 처리할 때는 트랜잭션을 작은 단위로 분할
- 읽기 전용 쿼리에는 적절한 격리 수준 사용 (읽기 일관성과 성능 균형)

### 1.4 autocommit 설정과 트랜잭션 성능의 관계

Aurora MySQL의 리더 노드에서는 트랜잭션과 autocommit 설정이 성능에 큰 영향을 미칩니다:

- **autocommit=0 (비활성화)**: 모든 SQL 문이 명시적 트랜잭션 내에서 실행되므로 커밋/롤백이 필요
- **autocommit=1 (활성화)**: 각 SQL 문이 자동으로 커밋되어 트랜잭션 오버헤드 감소

리더 노드에서 읽기 전용 쿼리는 autocommit=1 설정이 유리하지만, JPA/ORM을 사용하는 경우 기본적으로 트랜잭션 내에서 실행되어 autocommit=0으로 동작하는 경우가 많습니다.

```sql
-- 세션 레벨에서 autocommit 설정 확인
SHOW VARIABLES LIKE 'autocommit';

-- autocommit 활성화 (읽기 전용 쿼리에 유리)
SET autocommit = 1;
```

읽기 전용 쿼리가 autocommit=0으로 실행되면 트랜잭션이 종료되지 않아 언두 로그(RollbackSegment)가 계속 증가하여 성능 저하가 발생할 수 있습니다.

## 2. 애플리케이션-데이터베이스 연동 최적화

### 2.1 JPA/Hibernate와 Aurora MySQL 연동 최적화

JPA/Hibernate를 Aurora MySQL 3.x와 함께 사용할 때 주의해야 할 점:

- **@Transactional(readOnly = true)** 설정의 이해
  - 이 설정은 Hibernate의 영속성 컨텍스트를 최적화하지만 실제로는 트랜잭션이 생성됨
  - 리더 노드에서는 여전히 autocommit=0으로 동작하여 성능 저하 가능성 있음

- **적절한 캐싱 전략 활용**
  - 2차 캐시를 활용하여 데이터베이스 조회 최소화
  - 읽기 전용 데이터는 적극적으로 캐싱

- **배치 처리 최적화**
  - 대량 데이터 처리 시 배치 크기 최적화 (hibernate.jdbc.batch_size)
  - 주기적인 flush와 clear로 메모리 사용량 관리

### 2.2 읽기 전용 트랜잭션 처리 전략

리더 노드의 성능을 최대화하기 위한 읽기 전용 트랜잭션 처리 전략:

1. **별도의 읽기 전용 데이터소스 구성**:
   ```java
   @Bean(name = "readOnlyDataSource")
   public DataSource readOnlyDataSource() {
       HikariDataSource dataSource = new HikariDataSource();
       dataSource.setReadOnly(true);
       dataSource.setAutoCommit(true);  // 중요: autoCommit을 true로 설정
       return dataSource;
   }
   ```

2. **트랜잭션 전파 수준 조정**:
   ```java
   @Transactional(propagation = Propagation.NOT_SUPPORTED, readOnly = true)
   public Data readData() {
       // 트랜잭션 없이 실행됨
   }
   ```

3. **JdbcTemplate 활용**:
   복잡한 읽기 전용 쿼리는 JPA 대신 JdbcTemplate을 사용하여 트랜잭션 오버헤드 없이 처리

### 2.3 리더/라이터 노드를 위한 데이터소스 구성

Aurora MySQL의 리더/라이터 구조를 활용한 데이터소스 구성:

```java
@Configuration
public class DataSourceConfig {
    @Bean
    @Primary
    @ConfigurationProperties("spring.datasource.writer")
    public DataSource writerDataSource() {
        return DataSourceBuilder.create().build();
    }
    
    @Bean("readerDataSource")
    @ConfigurationProperties("spring.datasource.reader")
    public DataSource readerDataSource() {
        return DataSourceBuilder.create().build();
    }
    
    @Bean
    public RoutingDataSource routingDataSource() {
        RoutingDataSource routingDataSource = new RoutingDataSource();
        Map<Object, Object> targetDataSources = new HashMap<>();
        targetDataSources.put(DataSourceType.WRITER, writerDataSource());
        targetDataSources.put(DataSourceType.READER, readerDataSource());
        routingDataSource.setTargetDataSources(targetDataSources);
        routingDataSource.setDefaultTargetDataSource(writerDataSource());
        return routingDataSource;
    }
}
```

properties 파일 설정:
```properties
# 라이터 엔드포인트 설정
spring.datasource.writer.jdbc-url=jdbc:mysql://aurora-cluster-endpoint/dbname
spring.datasource.writer.username=master_user
spring.datasource.writer.password=password

# 리더 엔드포인트 설정
spring.datasource.reader.jdbc-url=jdbc:mysql://aurora-reader-endpoint/dbname
spring.datasource.reader.username=reader_user
spring.datasource.reader.password=password
spring.datasource.reader.auto-commit=true
```

### 2.4 레거시 시스템에서의 안전한 최적화 방법

기존 레거시 시스템의 성능을 안전하게 개선하는 방법:

1. **트랜잭션 범위 최소화**:
   ```java
   // 비효율적 방식
   @Transactional
   public void processLargeOperation() {
       // 데이터 로딩 (읽기 작업)
       // 오래 걸리는 처리 작업
       // 결과 저장 (쓰기 작업)
   }

   // 최적화 방식
   public void processLargeOperation() {
       // 트랜잭션 없이 데이터 로딩
       List<Data> data = dataService.loadData();
       
       // 비즈니스 로직 (트랜잭션 없이 처리)
       List<Result> results = processData(data);
       
       // 쓰기 작업만 트랜잭션으로 처리
       dataService.saveResults(results);
   }
   ```

2. **성능 이슈가 심한 API에 선별적 최적화 적용**:
   - 모니터링을 통해 식별된 성능 이슈 API만 우선 최적화
   - 나머지는 기존 방식 유지하여 위험 최소화

3. **점진적 개선 전략**:
   - 단계적으로 최적화 적용하고 결과 모니터링
   - 새로운 기능부터 최적화된 패턴 적용

## 3. 쿼리 최적화 및 인덱스 전략

### 3.1 Aurora MySQL 3.x 인덱스 활용

인덱스 설계에 대한 상세 가이드는 [design_table_index.md](./design_table_index.md)를 참조하세요.

주요 고려사항:
- 쿼리 패턴에 맞는 적절한 인덱스 구성
- 복합 인덱스 컬럼 순서 최적화
- 불필요한 인덱스 제거로 쓰기 성능 개선

### 3.2 쿼리 실행 계획 분석과 최적화

쿼리 실행 계획 분석 및 최적화에 대한 상세 내용은 [optimization_query.md](./optimization_query.md)를 참조하세요.

Aurora MySQL 3.x에서 특히 주의할 점:
- EXPLAIN ANALYZE는 개발/테스트 환경에서만 자유롭게 사용하고, 운영에서는 제한적으로 사용
- 실행 계획 캐싱과 관련된 Aurora 특화 동작 이해
- 리더 노드와 라이터 노드에서 쿼리 계획이 다를 수 있음을 인지

### 3.3 자주 발생하는 성능 문제와 해결 방법

Aurora MySQL 3.x에서 자주 발생하는 성능 문제와 해결 방법:

- **잘못된 인덱스 사용**:
  - 인덱스 힌트 활용
  - 쿼리 재작성

- **대용량 일괄 처리 성능 저하**:
  - 배치 단위로 분할 처리
  - 시간 기반 파티셔닝 활용

- **느린 JOIN 쿼리**:
  - JOIN 순서 최적화
  - 서브쿼리 대신 JOIN 활용

## 4. 시스템 파라미터 설정 가이드

### 4.1 핵심 성능 파라미터

Aurora MySQL 3.x 성능에 영향을 미치는 주요 파라미터:

| 파라미터 | 권장 값 | 설명 |
|---------|--------|-----|
| innodb_buffer_pool_size | 인스턴스 메모리의 70-80% | InnoDB 버퍼 풀 크기 |
| innodb_buffer_pool_instances | 8 | 버퍼 풀 인스턴스 수 |
| max_connections | 워크로드에 맞게 조정 | 최대 동시 연결 수 |
| innodb_flush_log_at_trx_commit | 1 (안정성 우선), 2 (성능 중시) | 트랜잭션 커밋 시 로그 동기화 방식 (Aurora MySQL 3.x에서는 값 1의 동작 변경됨. 값이 1이라도 성능 향상을 위해 울타리프스의 group commit 메커니즘을 사용하며, 일반 MySQL 8.0의 전통적인 동작과 다름) |
| innodb_flush_method | O_DIRECT | 데이터 파일 플러시 방식 |

### 4.2 워크로드 유형별 최적 파라미터 구성

**읽기 중심 워크로드**:
{{ ... }}
- innodb_buffer_pool_size: 더 큰 값 설정
- query_cache_type: 0 (Aurora에서는 사용하지 않음)
- innodb_read_io_threads: 16

**쓰기 중심 워크로드**:
- innodb_flush_log_at_trx_commit: 2 (성능 중시)
- innodb_write_io_threads: 16
- binlog_format: ROW

**혼합 워크로드**:
- innodb_buffer_pool_size: 인스턴스 메모리의 75%
- innodb_flush_log_at_trx_commit: 1
- max_connections: 적절히 높게 설정

### 4.3 리더/라이터 노드별 차별화된 파라미터 설정

**라이터 노드 파라미터**:
- innodb_flush_log_at_trx_commit = 1 (데이터 안정성 우선)
  - **중요**: Aurora MySQL 3.x(MySQL 8.0)에서는 1과 2 값의 동작이 변경됨. 값이 1이라도 성능 향상을 위해 울타리프스의 group commit 메커니즘을 사용하며, 일반 MySQL 8.0의 전통적인 동작과 다름
- sync_binlog = 1
- innodb_doublewrite = 1

**리더 노드 파라미터**:
- read_only = 1
- innodb_adaptive_hash_index = ON (읽기 성능 향상)
- max_connections = 더 높게 설정 (읽기 요청 처리)

## 5. 대용량 데이터 처리 전략

### 5.1 파티셔닝 활용

Aurora MySQL 3.x에서 파티셔닝을 활용한 대용량 데이터 관리:

- 오더와 비례해서 증가하는 테이블은 파티션 구조 및 데이터 보관 정책 필요
- 파티션당 10-30GB로 유지하는 것이 관리 및 성능 관점에서 적합
- 최대 8,192개 파티션 지원

```sql
-- 날짜 기반 RANGE 파티셔닝 예시
CREATE TABLE orders (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_date DATE NOT NULL,
    customer_id INT NOT NULL,
    -- 기타 컬럼
    INDEX idx_order_date (order_date)
) ENGINE=InnoDB
PARTITION BY RANGE (TO_DAYS(order_date)) (
    PARTITION p202401 VALUES LESS THAN (TO_DAYS('2024-02-01')),
    PARTITION p202402 VALUES LESS THAN (TO_DAYS('2024-03-01')),
    PARTITION p202403 VALUES LESS THAN (TO_DAYS('2024-04-01')),
    PARTITION p202404 VALUES LESS THAN (TO_DAYS('2024-05-01')),
    PARTITION p202405 VALUES LESS THAN (TO_DAYS('2024-06-01')),
    PARTITION future VALUES LESS THAN MAXVALUE
);
```

### 5.2 배치 처리 최적화

대용량 데이터 배치 처리 최적화 전략:

1. **청크 단위 처리**:
   ```sql
   -- 10,000건씩 처리
   SET @chunk = 10000;
   SET @offset = 0;
   
   process_chunk:
   UPDATE large_table 
   SET processed = 1 
   WHERE processed = 0 
   ORDER BY id 
   LIMIT @chunk;
   
   -- 처리된 행 수 확인하고 계속 진행 여부 결정
   ```

2. **파티션 단위 처리**:
   특정 파티션만 대상으로 처리하여 처리 범위 제한

3. **주기적 커밋**:
   트랜잭션 크기를 제한하여 언두 로그 부하 감소

### 5.3 아카이빙 및 데이터 보관 정책

데이터 아카이빙 및 보관 전략:

- 파티션 교체를 통한 효율적인 아카이빙
  ```sql
  -- 오래된 파티션 분리
  ALTER TABLE orders EXCHANGE PARTITION p202401 WITH TABLE orders_archive_202401;
  ```

- 클라우드 스토리지(S3)를 활용한 콜드 데이터 저장
- 데이터 보관 기간 및 정책 명확화
- 자동화된 아카이빙 프로세스 구축

## 6. 연결 관리 및 연결 풀 최적화

### 6.1 Aurora MySQL 최적 연결 풀 설정

Aurora MySQL 3.x와 함께 사용하는 연결 풀 설정 최적화:

**HikariCP 권장 설정**:
```properties
# 기본 설정
spring.datasource.hikari.connection-timeout=20000        # 20초
spring.datasource.hikari.minimum-idle=10                # 최소 유휴 연결 수
spring.datasource.hikari.maximum-pool-size=20           # 최대 풀 크기
spring.datasource.hikari.idle-timeout=600000            # 10분
spring.datasource.hikari.max-lifetime=1800000           # 30분

# Aurora 최적화 설정
spring.datasource.hikari.connection-test-query=SELECT 1
spring.datasource.hikari.validation-timeout=10000       # 10초
```

**인스턴스 유형별 연결 풀 권장 크기**:
| 인스턴스 클래스 | 권장 최대 연결 수 |
|----------------|------------------|
| db.t3.small    | 45               |
| db.t3.medium   | 90               |
| db.r5.large    | 180              |
| db.r5.xlarge   | 270              |
| db.r5.2xlarge  | 540              |
| db.r5.4xlarge  | 1,000            |

### 6.2 연결 누수 방지 및 모니터링

연결 누수(Connection Leak) 방지 전략:

1. **연결 누수 모니터링 쿼리**:
   ```sql
   SELECT id, user, host, db, command, time, state, info 
   FROM information_schema.processlist
   WHERE command = 'Sleep' AND time > 300
   ORDER BY time DESC;
   ```

2. **애플리케이션에서 누수 방지**:
   - try-with-resources 구문 사용
   - 트랜잭션 경계 명확히 설정
   - 정기적인 애플리케이션 로그 검토

3. **연결 타임아웃 설정**:
   - wait_timeout 및 interactive_timeout 파라미터 조정
   - 애플리케이션의 트랜잭션 타임아웃 설정

### 6.3 부하 증가 시 연결 관리 전략

갑작스러운 트래픽 증가 시 연결 관리:

1. **점진적 풀 확장**: 연결 폭증 시 점진적으로 풀 크기 확장
2. **연결 제한 정책**: 중요 서비스에 대한 연결 우선순위 설정
3. **장애 격리 패턴**: 서비스 간 연결 풀 격리로 장애 전파 방지

## 7. Aurora 복제 지연 모니터링 및 최적화

### 7.1 복제 지연 원인과 진단

복제 지연의 주요 원인:
- 라이터 노드의 높은 쓰기 부하
- 리더 노드에서 실행되는 무거운 쿼리
- 리더 노드의 리소스 부족

진단 쿼리:
```sql
-- Aurora MySQL 3.x에서 복제 지연 확인
SHOW REPLICA STATUS\G

-- 복제 지연 시간 확인 (초 단위)
SELECT ROUND(TIMESTAMPDIFF(MICROSECOND, 
                            result->>'$.serverTime', 
                            NOW(6))/1000000, 1) AS replica_lag 
  FROM mysql.aurora_replica_status() 
 WHERE SERVER_ID != 'master';
```

### 7.2 복제 지연 최소화 전략

1. **쓰기 작업 최적화**:
   - 대량 DML 작업 분할 실행
   - 단일 트랜잭션에서 변경하는 행 수 제한
   - 트랜잭션 크기와 지속 시간 최소화

2. **리더 노드 쿼리 최적화**:
   - 리더 노드에서 무거운 분석 쿼리 제한
   - 읽기 부하 분산을 위한 다중 리더 노드 활용

3. **인프라 확장**:
   - 리더 노드 스케일업 또는 추가 리더 노드 배포
   - 라이터 노드 인스턴스 유형 업그레이드

## 8. Aurora 특화 기능 활용

### 8.1 병렬 쿼리 최적화

Aurora MySQL 병렬 쿼리 기능 활용:

- **활성화 조건**:
  - Aurora MySQL 3.x 호환 클러스터
  - db.r* 인스턴스 타입
  - aurora_parallel_query=ON 파라미터 설정

- **병렬 쿼리 모니터링**:
  ```sql
  -- 병렬 쿼리 실행 여부 확인
  SELECT * FROM information_schema.aurora_pq_status;
  ```

- **병렬 쿼리가 효과적인 시나리오**:
  - 대용량 테이블 전체 스캔
  - 대량 데이터 집계 작업
  - 인덱스를 사용하지 않는 복잡한 조인 작업

### 8.2 글로벌 데이터베이스 성능 최적화

Aurora 글로벌 데이터베이스 활용 시 성능 최적화:

- **리전 간 지연 고려**:
  - 리전 간 복제 지연 모니터링
  - 지역적으로 가까운 리전에 읽기 요청 라우팅

- **재해 복구 전략**:
  - 계획된 장애 조치(Failover) 테스트 정기 수행
  - 재해 복구 시간 목표(RTO) 및 복구 지점 목표(RPO) 검증

### 8.3 백트래킹 기능 활용

Aurora 백트래킹 기능 최적화 활용:

- **백트래킹 창 설정**:
  - 비즈니스 요구사항에 맞게 백트래킹 창 설정
  - 비용과 복구 능력 간 균형점 찾기

- **운영 모범 사례**:
  - 주요 변경 전 수동 DB 스냅샷 생성
  - 백트래킹 테스트 정기적 수행

## 9. 클라우드 환경에서의 비용-성능 최적화

### 9.1 인스턴스 크기와 성능 상관관계

워크로드에 적합한 인스턴스 선택:

- **CPU 바운드 워크로드**: r5, r6g, x2g 인스턴스 권장
- **메모리 바운드 워크로드**: r5, x2g, z1d 인스턴스 권장
- **I/O 바운드 워크로드**: io2, r6gd 인스턴스 권장

### 9.2 비용 효율적인 오토스케일링

Aurora 오토스케일링 최적화:

- **리더 노드 오토스케일링 설정**:
  - CPU 사용률 기반 정책 구성
  - 일일 트래픽 패턴에 맞는 예약 스케일링 설정

- **비용 최적화 전략**:
  - 불필요한 리더 노드 제거를 위한 스케일 인 정책 설정
  - 인스턴스 종료 보호 기능 활성화

### 9.3 스토리지 I/O 최적화

Aurora 스토리지 비용 및 성능 최적화:

- **I/O 최적화 쿼리 작성**:
  - 효율적인 인덱스 설계로 I/O 감소
  - 불필요한 대용량 데이터 전송 방지

- **스토리지 비용 관리**:
  - 백업 보존 기간 최적화
  - 적절한 아카이빙 정책으로 스토리지 사용량 관리

## 10. 일반적인 안티 패턴 및 최적화 사례

### 10.1 Aurora MySQL 환경의 주요 안티 패턴

자주 발생하는 성능 저하 패턴:

1. **과도한 커넥션 생성**:
   - 각 요청마다 새 연결 생성
   - 연결 풀 크기 과다 설정

2. **비효율적인 트랜잭션 관리**:
   - 트랜잭션 내에서 불필요한 외부 API 호출
   - 과도하게 긴 트랜잭션 유지

3. **잘못된 인덱스 사용**:
   - 조건절에 함수 사용으로 인덱스 사용 불가
   - 복합 인덱스 컬럼 순서 오류

4. **비효율적인 페이징 처리**:
   - OFFSET 사용 시 대용량 데이터에서 성능 저하
   - 키셋 페이징(Keyset Pagination) 미사용

### 10.2 실제 사례 기반 최적화 전략

실제 성능 개선 사례:

**사례 1: 읽기 전용 트랜잭션 최적화**
- 문제: 리더 노드에서 불필요한 트랜잭션으로 RollbackSegment 증가
- 해결: 별도의 읽기 전용 데이터소스 구성 및 autocommit=true 설정
- 결과: 50% 이상의 리더 노드 부하 감소

**사례 2: 대용량 데이터 처리 최적화**
- 문제: 일괄 처리 시 트랜잭션 타임아웃 및 리소스 고갈
- 해결: 청크 단위 처리 및 백그라운드 작업 구현
- 결과: 처리 시간 75% 단축 및 시스템 안정성 향상

### 10.3 성능 디버깅 방법론

체계적인 성능 문제 해결 접근법:

1. **문제 정의**:
   - 성능 저하의 정확한 증상 파악
   - 재현 가능한 시나리오 확인

2. **데이터 수집**:
   - 성능 지표 수집 (CPU, 메모리, I/O, 쿼리 수행 시간)
   - 로그 및 슬로우 쿼리 분석

3. **병목 지점 식별**:
   - 리소스 사용률 분석
   - 쿼리 실행 계획 검토
   - 대기 이벤트 분석

4. **해결책 구현 및 검증**:
   - 하나의 변경만 적용 후 효과 측정
   - A/B 테스트로 개선 효과 검증

## 11. 운영 환경 변경 관리

### 11.1 스키마 변경의 안전한 배포 전략

운영 환경에서 스키마 변경 최적화:

- **무중단 스키마 변경 도구 활용**:
  - gh-ost, pt-online-schema-change 등 활용
  - Aurora MySQL 3.x의 INSTANT 알고리즘 활용

- **안전한 변경 순서**:
  ```
  1. 새 컬럼 추가 (NULL 허용)
  2. 코드 배포 (새 컬럼 읽기/쓰기)
  3. 데이터 마이그레이션
  4. NOT NULL 제약 추가
  ```

- **실행 계획 변경 관리**:
  - 스키마 변경 후 쿼리 실행 계획 검증
  - 성능 테스트 환경에서 사전 검증

### 11.2 대규모 데이터 마이그레이션 접근법

대규모 데이터 마이그레이션 전략:

1. **온라인 마이그레이션**:
   - 청크 단위 점진적 마이그레이션
   - 복제 지연 모니터링 및 관리

2. **이중 쓰기(Dual Writing) 접근법**:
   - 기존 테이블과 새 테이블 모두에 쓰기
   - 데이터 일관성 검증 후 전환

3. **잠금 최소화 전략**:
   - 읽기 잠금만 사용하여 마이그레이션
   - 짧은 쓰기 잠금으로 전환 완료

### 11.3 운영 영향을 최소화하는 인덱스 추가/수정 전략

인덱스 작업 최적화:

- **백그라운드 인덱스 생성**:
  ```sql
  ALTER TABLE orders ADD INDEX idx_customer_date (customer_id, order_date) ALGORITHM=INPLACE, LOCK=NONE;
  ```

- **인덱스 교체 전략**:
  ```sql
  -- 1. 새 인덱스 생성
  CREATE INDEX idx_customer_date_new ON orders (customer_id, order_date);
  
  -- 2. 애플리케이션에서 새 인덱스 사용하도록 변경
  
  -- 3. 이전 인덱스 제거 (적절한 모니터링 기간 후)
  ALTER TABLE orders DROP INDEX idx_customer_date_old;
  ```

- **인덱스 변경 모니터링**:
  - 인덱스 생성 중 복제 지연 모니터링
  - 인덱스 생성 진행 상황 확인

## 12. Aurora과 애플리케이션 간 캐싱 전략

### 12.1 적절한 캐시 계층화 전략

다중 계층 캐싱 접근법:

1. **로컬 캐시**:
   - 변경이 적은 데이터 (코드 테이블, 설정 등)
   - 짧은 TTL 설정으로 일관성 보장

2. **분산 캐시 (Redis/ElastiCache)**:
   - 세션 데이터, 사용자 프로필 등
   - 서비스 간 공유 데이터

3. **애플리케이션 레벨 캐싱**:
   - Spring Cache 또는 Hibernate 2차 캐시 활용
   - 적절한 캐시 무효화 전략 구현

### 12.2 쿼리 결과 캐싱 최적화

효과적인 쿼리 결과 캐싱:

- **캐시 대상 선정 기준**:
  - 읽기 비율이 높은 데이터
  - 계산 비용이 높은 쿼리 결과
  - 실시간성이 덜 중요한 데이터

- **캐시 키 설계**:
  - 유의미한 키 구조 설계
  - 선택적 캐시 무효화 가능하도록 설계

### 12.3 캐시 무효화 전략

효과적인 캐시 무효화 방법:

1. **시간 기반 무효화**:
   - TTL(Time To Live) 설정
   - 데이터 변경 빈도에 맞게 TTL 조정

2. **이벤트 기반 무효화**:
   - 데이터 변경 시 관련 캐시 명시적 무효화
   - 메시지 큐를 통한 분산 무효화 처리

3. **캐시 패턴**:
   - Write-Through: 데이터 쓰기와 동시에 캐시 업데이트
   - Write-Behind: 캐시 먼저 업데이트 후 비동기로 DB 업데이트
   - Cache-Aside: 필요할 때만 캐시 로드

## 13. 모니터링 및 성능 분석

성능 모니터링 및 분석에 대한 상세 내용은 [monitoring_query_aurora_mysql.md](./monitoring_query_aurora_mysql.md)를 참조하세요.
