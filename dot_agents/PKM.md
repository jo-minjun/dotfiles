# PKM (Obsidian)

## 볼트 경로
- `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/PKM`

## 폴더 구조 (PARA)
- `00.Projects/` - 진행 중인 프로젝트
- `01.Areas/` - 지속적 관심 영역
- `02.Resources/` - 참고 자료
- `03.Archives/` - 완료/비활성 항목
- `99.Assets/` - 첨부 파일 (자동 저장 경로)
- `Z.ETC/10.Templates/` - 노트 템플릿

## 노트 컨벤션
- frontmatter 필수 필드: `type`, `tags`, `createdAt`
  - type: Project, Area, Resource, Archive, Inbox
  - createdAt: ISO 8601 형식 (예: `2026-02-24T08:35:16+09:00`)
- 파일명: 공백 허용, kebab-case 사용하지 않음 (예: `Paddle 결제 구조 조사.md`)
- 링크: 에셋 임베드는 wikilink (`![[]]`), 외부 URL은 markdown link
- 새 노트 생성 시 PARA 분류에 맞는 폴더에 배치하라

## 접근 규칙
- 기존 노트 수정은 사용자의 명시적 승인 후에만 진행하라
- 노트 삭제는 금지하라
- 새 노트 생성 시 폴더와 frontmatter를 확인받아라
