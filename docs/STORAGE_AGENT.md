# Storage Agent

Ubuntu Worker에서 실행되는 저장소 메타데이터 관리 모듈이다.

## 현재 기능

- SQLite Inventory
- Scan 실행 이력
- 파일 메타데이터 관리
- Missing 상태 추적
- 오류 기록
- 읽기 전용 Inventory 리포트
- Duplicate Preview
- Duplicate 신뢰성 검증

## 데이터베이스

경로:

    agents/storage-agent/data/storage.db

운영 DB와 백업 DB는 Git에 커밋하지 않는다.

## 안전 정책

- 자동 삭제 금지
- Archive를 Master Repository로 취급
- Immich 및 Nextcloud 신규 분석 제외
- 삭제 전 사용자 승인 필수
- 기존 SHA256 결과 보존
