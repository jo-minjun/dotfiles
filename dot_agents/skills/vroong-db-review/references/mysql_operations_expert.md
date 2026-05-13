# MySQL 운영 스키마 변경 전문가 가이드

## 역할 개요

MySQL 운영 스키마 변경 전문가는 프로덕션 환경에서 데이터베이스 스키마 변경을 계획, 검증, 실행하는 역할을 담당합니다. Aurora MySQL 3.x(MySQL 8.0) 환경에서 안전하고 효율적인 스키마 변경을 위한 전문 지식과 프로세스를 제공합니다.

## 주요 책임

1. **DDL 및 DML 작업 검토**
   - 개발자가 요청한 스키마 변경 작업의 영향도 분석
   - 적절한 알고리즘과 잠금 방식 선택
   - 데이터베이스 성능과 가용성에 미치는 영향 평가

2. **작업 계획 수립**
   - 스키마 변경 작업의 순서와 타이밍 결정
   - 롤백 계획 수립
   - 변경 작업 중 및 이후의 모니터링 계획 준비

3. **실행 및 모니터링**
   - 계획된 변경 작업 실행
   - 작업 진행 상황 모니터링
   - 문제 발생 시 즉각적인 대응 및 롤백

4. **문서화 및 지식 공유**
   - 수행된 작업 기록 및 문서화
   - 팀 내 모범 사례 공유
   - 운영 프로세스 개선을 위한 피드백 제공

## 핵심 검토 영역

### 1. DDL 작업 영향도 분석

#### 알고리즘 및 잠금 방식 선정

- **ALGORITHM=INSTANT** (MySQL 8.0.12부터 도입, MySQL 8.0.29부터 기본값)
  - 메타데이터만 수정하는 가장 경량화된 작업
  - 잠금 없이 즉시 적용 가능
  - 적용 가능 작업:
    - 컬럼 추가(특정 위치)
    - 기본값 변경
    - 가상 컬럼 추가
    - 인덱스 타입 변경(USING BTREE/HASH)
    - 외래 키 제약 조건 추가/삭제
  - 제약 사항:
    - 컬럼 삭제 시 동일 문장에서 다른 ALGORITHM=INSTANT를 지원하지 않는 작업과 결합 불가
    - 테이블 구조에 따라 INSTANT가 지원되지 않을 수 있으며, 이 경우 INPLACE로 대체됨

- **ALGORITHM=INPLACE, LOCK=NONE**
  - 테이블 구조를 변경하지만 복사는 필요 없는 작업
  - 작업 시작과 끝에 메타데이터 잠금을 획득하며, 동시 DML 작업 가능
  - 적용 가능 작업:
    - 인덱스 생성/삭제/재명명
    - 컬럼 추가(테이블 끝)
    - ENUM/SET 값 추가
    - 컬럼 순서 변경
    - FULLTEXT 인덱스 추가(첫 번째 이후)
  - 주의 사항:
    - 대용량 테이블에서도 상대적으로 빠르게 수행 가능하나 부하는 발생함
    - 인덱스 생성 시 전체 트랜잭션이 완료될 때까지 기다림(최신 데이터 반영을 위해)

- **ALGORITHM=COPY, LOCK=SHARED**
  - 테이블을 복사하여 작업을 수행
  - 작업 중 읽기만 가능하며 쓰기는 불가능
  - 주로 필요한 작업:
    - 컬럼 타입 변경
    - 테이블 압축 방식 변경
    - CHARACTER SET 변경
    - 첫 번째 FULLTEXT 인덱스 추가(FTS_DOC_ID 컬럼이 없는 경우)
  - 가능한 피해야 하며, 트래픽이 거의 없는 시간에 수행 필요

#### 프라이머리 키 작업 특이사항

- 프라이머리 키 추가/변경/삭제는 항상 테이블 데이터 재구성이 필요한 고비용 작업
- ALGORITHM=INPLACE로 수행하더라도 내부적으로 데이터 복사가 발생함
- 프라이머리 키는 테이블 생성 시 정의하는 것이 가장 효율적
- 프라이머리 키 변경 작업은 다음과 같은 이유로 ALGORITHM=COPY보다 ALGORITHM=INPLACE가 더 효율적:
  - 언두 로깅과 관련 리두 로깅이 필요 없음
  - 보조 인덱스 항목이 미리 정렬되어 순서대로 로드 가능
  - 보조 인덱스에 대한 무작위 삽입이 없어 변경 버퍼를 사용하지 않음

#### 고려사항
- 변경 작업이 트랜잭션 처리량에 미치는 영향
- 서비스 가용성에 미치는 영향
- 작업 실패 시 롤백 가능성

#### DROP COLUMN 주의사항

- **실행 영향도**:
  - MySQL 8.0 이상에서는 기본적으로 ALGORITHM=INPLACE, LOCK=NONE 지원
  - 테이블 크기에 따라 수행 시간이 달라지며, 대형 테이블의 경우 실행 시간이 길어짐
  - 데이터 사이즈는 줄어들지만, 테이블 건드리는 동안 자원 사용량이 높아짐

- **제한사항**:
  - 테이블에 외래 키가 있는 경우 해당 컬럼이 외래 키의 일부라면 먼저 외래 키를 제거해야 함
  - 기본값을 가진 컬럼을 삭제하는 경우 테이블 전체 복사가 필요할 수 있음
  - 포인트 인데스, 가상 컬럼 등을 포함한 컬럼은 제한사항 있을 수 있음

- **반드시 사전 확인해야 할 사항**:
  ```sql
  -- 삭제 전 컬럼을 참조하는 외래 키 확인
  SELECT TABLE_NAME, COLUMN_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
  FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
  WHERE REFERENCED_TABLE_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME = '테이블명'
  AND REFERENCED_COLUMN_NAME = '삭제할컬럼명';

  -- 해당 컬럼을 사용하는 트리거 확인
  SELECT TRIGGER_NAME, EVENT_MANIPULATION, ACTION_STATEMENT
  FROM INFORMATION_SCHEMA.TRIGGERS
  WHERE EVENT_OBJECT_SCHEMA = DATABASE()
  AND EVENT_OBJECT_TABLE = '테이블명';
  ```

- **안전한 컬럼 삭제 방법**:
  - 운영 환경에서 중요 컬럼 삭제 시 먼저 INVISIBLE 처리 후 삭제 권장
  ```sql
  -- 컬럼을 INVISIBLE로 변경 (MySQL 8.0.23부터 ALGORITHM=INSTANT 지원)
  ALTER TABLE table_name
  MODIFY COLUMN column_name DATA_TYPE INVISIBLE,
  ALGORITHM=INSTANT;

  -- 애플리케이션이 오류 없이 동작하는지 관찰 (전체 컬럼 지정 시에는 안보임)
  -- 문제가 없는지 확인 후 컬럼 삭제 진행
  ALTER TABLE table_name
  DROP COLUMN column_name,
  ALGORITHM=INPLACE, LOCK=NONE;
  ```

  - **INVISIBLE 처리 주의사항**:
    - INVISIBLE 처리된 컬럼은 일반 쿼리에서는 자동으로 제외되지만, 명시적으로 지정하면 사용 가능
    - INVISIBLE 컬럼은 여전히 스토리지를 차지하며 인덱스도 업데이트됨
    - INVISIBLE 컬럼에 INSERT 시 명시적으로 컬럼명을 지정해야 함
    - INVISIBLE 상태에서도 외래 키, 인덱스, 트리거 등은 여전히 작동하므로 매우 주의 필요
    - `SELECT * FROM table` 쿼리에서는 결과에 포함되지 않지만, `SELECT column_name FROM table`로 직접 지정하면 여전히 가져올 수 있음
    - 모든 INVISIBLE 컬럼을 포함한 결과를 원할 경우 `SET SESSION sql_select_show_invisible=ON` 사용 가능

#### DROP TABLE 주의사항

- **실행 영향도**:
  - 상위 작업으로, 메타데이터 잠금 및 테이블 정의 삭제를 포함
  - 대형 테이블의 경우 해당 테이블을 참조하는 트랜잭션이 있으면 잠금 충돌 가능성 있음
  - 저장소 공간을 즉시 해제하지 않을 수 있음 (배경 클린업 프로세스에 의해 처리)

- **제한사항**:
  - 외래 키 제약조건이 있는 테이블은 CASCADE 옵션 없이 삭제 불가
  - 사용중인 테이블은 감시 처리될 때까지 삭제 프로세스가 지연될 수 있음
  - 파티션된 테이블의 경우 모든 파티션이 한번에 제거되므로 주의 필요

- **반드시 사전 확인해야 할 사항**:
  ```sql
  -- 해당 테이블을 참조하는 외래 키 확인
  SELECT TABLE_NAME, COLUMN_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
  FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
  WHERE REFERENCED_TABLE_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME = '삭제할테이블명';

  -- 해당 테이블을 사용하는 뷰 확인
  SELECT TABLE_NAME
  FROM INFORMATION_SCHEMA.VIEWS
  WHERE VIEW_DEFINITION LIKE '%\`삭제할테이블명\`%'
  AND TABLE_SCHEMA = DATABASE();

  -- 해당 테이블을 사용하는 트리거 확인
  SELECT TRIGGER_NAME, EVENT_MANIPULATION, ACTION_STATEMENT
  FROM INFORMATION_SCHEMA.TRIGGERS
  WHERE ACTION_STATEMENT LIKE '%\`삭제할테이블명\`%'
  AND TRIGGER_SCHEMA = DATABASE();
  ```

- **안전한 삭제 방법**:
  - 운영 환경에서 중요 테이블 삭제 시 먼저 이름 변경 후 삭제 권장
  ```sql
  -- RENAME TABLE은 기본적으로 메타데이터만 변경하는 작업
  RENAME TABLE table_name TO table_name_to_drop_20250527;

  -- 문제가 없는지 확인 후 삭제 진행
  -- DROP TABLE은 기본적으로 알고리즘이나 잠금 옵션을 지정할 수 없지만, 여기서는 명시적으로 문서화 용도
  DROP TABLE table_name_to_drop_20250527;
  ```

- **DROP TABLE 후 재생성 전략**
  - 테이블을 DROP 후 동일 이름으로 재생성하는 전략을 사용할 경우:
  1. 백업 테이블 생성:
     ```sql
     CREATE TABLE {테이블명}_bak_{YYYYMMDD} LIKE {테이블명};
     INSERT INTO {테이블명}_bak_{YYYYMMDD} SELECT * FROM {테이블명};
     ```
  2. 원본과 백업의 행 수 일치 확인
  3. DROP과 CREATE 사이에 서비스 장애가 발생하므로 트래픽이 적은 시간에 실행
  4. DDL이 nullable/default 컬럼만 추가하는 경우, 코드 배포 전에 DDL 적용 가능

### 2. DML 작업 영향도 분석

#### 대량 데이터 작업 처리 방안
- **대량 UPDATE/DELETE**
  - PK 기반으로 범위를 나누어 실행
  - LIMIT 절 사용하여 일괄 처리
  - 작업 간 지연 설정으로 부하 분산

#### 데이터 정합성 확보
- 백업 테이블 생성 여부 판단
- 작업 중 서비스 영향도 최소화 방안
- 롤백 시나리오 준비

### 3. 복제 환경 고려사항

- **복제 지연 모니터링**
  - `Seconds_Behind_Source` 값 확인
  - 작업 중 복제 오류 발생 가능성 평가

- **바이너리 로그 영향**
  - 대용량 변경 시 바이너리 로그 크기 고려
  - 필요시 `binlog_row_image=minimal` 설정 검토

- **BI DB 및 다중 복제 환경**
  - 보고용 데이터베이스 영향 평가
  - 복제 토폴로지에 따른 지연 전파 효과 분석

## 작업 프로세스

### 1. 사전 준비 및 분석

- **작업 요청 검토**
  - 티켓 내용 및 요구사항 분석
  - 필요시 요청자와 세부 사항 논의

- **테이블 상태 분석**
  - 테이블 크기, 인덱스, 트래픽 패턴 확인
  - `SHOW TABLE STATUS`, `INFORMATION_SCHEMA` 활용
  - 작업 대상 테이블의 의존성 파악

- **영향도 예측**
  - `EXPLAIN` 활용하여 쿼리 계획 검토
  - 테스트 환경에서 유사 작업 수행 및 결과 측정

### 2. 작업 계획 수립

- **최적 알고리즘 선택**
  - 각 변경 작업에 대한 최적 알고리즘 및 잠금 방식 결정
  - 가능한 `ALGORITHM=INSTANT` 또는 `ALGORITHM=INPLACE, LOCK=NONE` 선호

- **작업 순서 최적화**
  - 의존성을 고려한 작업 순서 결정
  - 잠금 요구사항이 다른 작업 그룹화

- **롤백 계획 수립**
  - 각 단계별 롤백 쿼리 준비
  - 백업 전략 결정

### 3. 사전 공지 및 협의

- **작업 사전 공지**
  - #상용배포 채널 등에 선공지
  - 서버명, 작업 종류, 영향 범위 명시
  - 관련 이해관계자에게 태그 또는 직접 알림

- **작업 일정 협의**
  - 트래픽이 적은 시간대 선택
  - 비상 대응 인력 확보 및 대기 계획

### 4. 실행 및 모니터링

- **작업 실행**
  - 계획된 순서대로 쿼리 실행
  - 각 단계 완료 후 영향 확인

- **실시간 모니터링**
  - 프로세스 목록 및 쿼리 실행 상태 모니터링
  ```sql
  SHOW PROCESSLIST;
  SELECT * FROM performance_schema.events_statements_current;
  ```

  - 잠금 상태 확인
  ```sql
  SELECT * FROM performance_schema.data_locks;
  SELECT * FROM performance_schema.data_lock_waits;
  SELECT * FROM INFORMATION_SCHEMA.INNODB_TRX;
  ```

  - 복제 상태 확인
  ```sql
  SHOW REPLICA STATUS\G
  ```

- **문제 대응**
  - 문제 발생 시 미리 준비된 롤백 계획 실행
  - 지연 발생 시 작업 속도 조절

### 5. 작업 완료 및 문서화

- **결과 검증**
  - 변경 작업 성공 여부 확인
  - 애플리케이션 정상 동작 확인
  - 복제 상태 정상 여부 확인

- **작업 결과 보고**
  - 티켓에 작업 결과 기록
  - 예상과 다른 상황 발생 시 원인 분석 및 기록

- **지식 공유**
  - 학습된 내용 및 프로세스 개선점 공유
  - 필요시 문서 및 가이드라인 업데이트

## 모범 사례 및 주의사항

### 모범 사례

1. **항상 ALGORITHM과 LOCK 명시**
   - 모든 DDL 작업에 ALGORITHM과 LOCK 절을 명시
   - 명시하지 않을 경우 MySQL이 가장 제한적인 방식을 선택할 수 있음
   - MySQL 8.0.29부터는 기본적으로 가능하면 ALGORITHM=INSTANT 사용
   ```sql
   ALTER TABLE table_name
   ADD COLUMN new_column INT,
   ALGORITHM=INPLACE, LOCK=NONE;
   ```

2. **작업 분할**
   - 대규모 변경은 작은 단위로 분할하여 실행
   - 한 번에 하나의 변경 작업만 실행
   - 여러 DDL 문을 조합하는 것보다 개별 실행이 안전함

3. **변경 전 테스트**
   - 실제 환경과 유사한 데이터로 테스트 환경에서 변경 작업 검증
   - 작업 완료 시간 및 리소스 사용량 측정
   - EXPLAIN 출력에서 인덱스 사용 확인

4. **백업 확보**
   - 중요 변경 전 적절한 백업 확보
   - 특히 ALGORITHM=COPY 작업 전에는 필수
   - Aurora의 경우 스냅샷 또는 백트래킹 기능 활용

5. **병렬 스레드 최적화**
   - MySQL 8.0은 일부 DDL 작업에 병렬 스레드 사용 가능
   - `innodb_ddl_threads` 시스템 변수로 스레드 수 조정 가능(기본값: 4)
   - 대형 테이블의 인덱스 생성 시 병렬 처리로 성능 향상 가능

### 주의사항

1. **Online DDL 한계 인식**
   - Online DDL로 명시되어 있더라도 실제로는 부하 발생 가능
   - 대용량 테이블의 경우 트래픽이 적은 시간대 작업 권장
   - 테이블 파티셔닝이 적용된 경우, 일부 DDL 작업이 제한될 수 있음

2. **메타데이터 잠금 고려**
   - DDL 작업은 메타데이터 잠금을 획득하므로 다른 DDL과 충돌 가능
   - 동시에 여러 DDL 작업 실행 자제
   - `performance_schema.metadata_locks` 테이블로 현재 메타데이터 잠금 모니터링 가능

3. **Online DDL 실패 시 복구**
   - 온라인 DDL 작업이 실패하면 MySQL이 자동으로 롤백을 시도함
   - 롤백 실패 시 수동 복구가 필요할 수 있음
   - `information_schema.INNODB_TEMP_TABLE_INFO`로 임시 테이블 상태 확인 가능

4. **트리거 및 외래 키 영향**
   - 테이블에 트리거가 있는 경우 ALGORITHM=INSTANT가 제한될 수 있음
   - 외래 키 제약 조건이 있는 테이블은 구조 변경 시 추가 고려 필요

5. **MySQL 8.0 버전별 차이점**
   - 8.0.12: ALGORITHM=INSTANT 도입
   - 8.0.17: 인덱스 재정렬 기능 개선
   - 8.0.29: INSTANT가 기본 알고리즘으로 변경
   - Aurora MySQL 3.x 버전별 호환성 확인 필요

3. **복제 지연 모니터링**
   - 작업 중 및 이후 복제 지연 모니터링 필수
   - 지연 발생 시 원인 분석 및 조치

4. **대량 DML 주의**
   - 대량 UPDATE/DELETE는 언두 로그 증가 및 성능 저하 유발
   - 소량으로 나누어 실행하고 중간에 커밋

### 인덱스 INVISIBLE 처리

- **안전한 인덱스 삭제 전단계**
  - 인덱스를 삭제하기 전에 INVISIBLE 처리하여 영향도 테스트 가능
  - MySQL 8.0에서는 ALGORITHM=INPLACE, LOCK=NONE으로 수행 가능
  ```sql
  -- 인덱스를 INVISIBLE로 설정 (MySQL 8.0에서 ALGORITHM=INPLACE 사용)
  ALTER TABLE table_name
  ALTER INDEX index_name INVISIBLE,
  ALGORITHM=INPLACE, LOCK=NONE;

  -- 파트너 애플리케이션이 정상 동작하는지 확인 후 인덱스 삭제
  ALTER TABLE table_name
  DROP INDEX index_name,
  ALGORITHM=INPLACE, LOCK=NONE;
  ```

- **INVISIBLE 인덱스 주의사항**
  - 기본적으로 쿼리 옵티마이저가 무시하지만, 인덱스는 여전히 유지보수됨
  - 옵티마이저는 INVISIBLE 인덱스를 무시하고, 다른 인덱스를 사용할 수 있음
  - 인덱스 생성, 삭제, 변경 시 반영되며 스토리지 공간 차지
  - FORCE INDEX 힌트를 사용하면 INVISIBLE 인덱스도 사용 가능
  - `SET SESSION optimizer_switch='use_invisible_indexes=ON'`으로 세션 레벨에서 모든 INVISIBLE 인덱스 사용 가능

- **인덱스 상태 확인**
  ```sql
  -- 테이블의 INVISIBLE 인덱스 확인
  SELECT INDEX_NAME, IS_VISIBLE
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = '테이블명';

  -- 실행계획에서 INVISIBLE 인덱스 사용 여부 확인
  EXPLAIN SELECT * FROM table_name WHERE indexed_column = 'value';
  ```

- **제한사항**
  - PRIMARY KEY는 INVISIBLE로 설정할 수 없음
  - 외래 키 제약조건에 사용되는 인덱스는 INVISIBLE로 설정할 수 없음
  - FULLTEXT 인덱스와 SPATIAL 인덱스는 INVISIBLE 설정이 제한될 수 있음

## 성장 경로 및 학습 자원

### 전문성 개발
- MySQL 8.0 Online DDL 기능 및 제한사항 숙지
- InnoDB 스토리지 엔진 내부 구조 이해
- 성능 모니터링 및 분석 능력 향상

### 추천 학습 자원
- [MySQL 8.0 Reference Manual - Online DDL Operations](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl-operations.html)
- [MySQL InnoDB Cluster & High Availability Guide](https://dev.mysql.com/doc/refman/8.0/en/mysql-innodb-cluster-introduction.html)
- [High Performance MySQL](https://www.oreilly.com/library/view/high-performance-mysql/9781492080503/) (O'Reilly)

## 결론

MySQL 운영 스키마 변경 전문가는 프로덕션 환경에서의 안전하고 효율적인 데이터베이스 스키마 변경을 담당하는 중요한 역할입니다. 이 역할을 성공적으로 수행하기 위해서는 MySQL의 내부 동작 원리를 깊이 이해하고, 체계적인 접근 방식을 통해 변경 작업을 계획, 실행, 모니터링해야 합니다. 또한 지속적인 학습과 경험 공유를 통해 팀 전체의 데이터베이스 운영 역량을 향상시키는 데 기여해야 합니다.
