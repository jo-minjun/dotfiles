---
name: vroong-db-review
description: "VROONG 데이터베이스 스키마 설계 및 쿼리 최적화 리뷰 스킬. Aurora MySQL 3.x(MySQL 8.0) 기반 가이드라인에 따라 DDL, 스키마, 인덱스, 쿼리를 검토한다. 다음 상황에서 트리거: (1) 'DDL 리뷰해줘', '스키마 검토해줘' 등 DB 스키마 리뷰 요청 (2) '쿼리 최적화 리뷰', '쿼리 검토해줘' 등 쿼리 리뷰 요청 (3) PR에 DB 마이그레이션/DDL 변경사항이 포함된 경우 자동 트리거 (4) Flyway/Liquibase 등 DB 마이그레이션 파일 리뷰 시"
---

# VROONG Database Review

Aurora MySQL 3.x(MySQL 8.0) 기반 VROONG 데이터베이스 가이드라인에 따라 스키마 설계 및 쿼리를 리뷰한다.

## 리뷰 워크플로우

### 1. 리뷰 대상 식별

입력을 분류하여 해당 레퍼런스를 로드한다:

| 리뷰 유형 | 로드할 레퍼런스 |
|-----------|----------------|
| 컬럼 설계 (컬럼 추가/변경, 타입 선택, 명명) | `references/design_column.md` |
| 테이블/인덱스 설계 (CREATE TABLE, ALTER TABLE, 인덱스) | `references/design_table_index.md` |
| 쿼리 최적화 (SELECT, JOIN, 서브쿼리, 페이징) | `references/optimization_query.md` |
| 인덱스 최적화 (인덱스 추가/삭제/변경, 중복 분석) | `references/optimization_index.md` |
| Aurora MySQL 최적화 (JPA/트랜잭션, 커넥션 풀, 스키마 변경) | `references/optimization_aurora_mysql.md` |
| DDL 운영 변경 (프로덕션 스키마 변경 계획/실행) | `references/mysql_operations_expert.md` |

복합적인 리뷰(예: CREATE TABLE + 쿼리)는 관련 레퍼런스를 모두 로드한다.

**참고용 추가 레퍼런스** (필요 시에만 로드):
- `references/mysql_8_expert.md` — MySQL 8.0 특화 기능 활용 검토
- `references/monitoring_query_aurora_mysql.md` — 모니터링 쿼리 패턴
- `references/monitoring_query_aurora_postgresql.md` — PostgreSQL 모니터링
- `references/troubleshooting_aurora_mysql.md` — 장애 대응 패턴

### 2. 리뷰 수행

로드한 레퍼런스의 규칙을 하나씩 대조하며 검토한다. 모든 발견사항에 카테고리와 심각도를 태그한다.

#### 카테고리
- `[명명]` — 명명 규칙 위반 (snake_case, 복수형, 접두사/접미사 등)
- `[타입]` — 데이터 타입 선택 오류 (DECIMAL vs FLOAT, TINYINT 불리언 등)
- `[인덱스]` — 인덱스 설계 문제 (중복, 누락, 과다, 카디널리티)
- `[성능]` — 성능 저하 우려 (풀스캔, OFFSET 페이징, 함수 적용 등)
- `[설계]` — 테이블 구조/정규화 문제
- `[운영]` — DDL 안전성, ALGORITHM/LOCK 미지정 등
- `[문서]` — COMMENT 누락, 불충분한 설명

#### 심각도
- `경고` — 반드시 수정 필요 (가이드라인 명확한 위반, 장애 가능성)
- `주의` — 수정 권장 (모범 사례 미준수, 성능 리스크)
- `사소` — 개선 제안 (스타일, 가독성)

#### 출력 형식

```
## 리뷰 결과

### 경고
- [타입/경고] `price` 컬럼에 FLOAT 사용 → DECIMAL로 변경 필요 (근사값 문제)
- [명명/경고] 테이블명 `delivery`는 단수형 → `deliveries`로 변경

### 주의
- [인덱스/주의] `created_at` 단독 인덱스 — 범위 조건 컬럼은 복합 인덱스 뒤쪽에 배치 권장
- [문서/주의] `status` 컬럼 COMMENT에 코드 값 의미 누락

### 사소
- [명명/사소] `s3_url` → `{맥락}_s3_uri` 패턴 권장

### 통과 항목
- PK 설계: auto_increment BIGINT UNSIGNED ✓
- 문자셋: utf8mb4 + utf8mb4_general_ci ✓
```

### 3. 대안 제시

위반 사항마다 가이드라인에 부합하는 수정 예시(DDL/쿼리)를 함께 제공한다.
