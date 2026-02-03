# 개발 규칙

## 테스트
- 테스트 비활성화 금지, 반드시 수정할 것

## 코드 품질
- 컴파일되지 않는 코드 커밋 금지
- 사용하지 않는 import, 변수, 메서드는 즉시 삭제

## Java 코드 스타일
- 클래스 내 멤버 순서:
  1. 필드 (상수, static, instance 순)
  2. 생성자
  3. public 메서드
  4. protected/package-private 메서드
  5. private 메서드
  6. static inner class, inner enum (가장 하단)

## 문서화
- 추측 금지, 기존 코드로 검증할 것
- 불확실한 내용은 사용자에게 확인
- 다이어그램은 mermaid 사용
- 문서 수정 시 기존 포맷과 일관성 유지

## 주석
- 주석은 최소화
- what, how 주석 금지
- why만 주석으로 남길 것
- TODO, FIX 주석에는 날짜와 작성자 포함

## 도구 사용
- 라이브러리 문서: Context7 우선, 실패 시 Fetch/Search
- Notion, Jira, Confluence, Github: MCP 도구 우선

## 커밋
- 커밋 메시지는 한글로 작성
