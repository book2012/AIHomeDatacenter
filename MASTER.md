# AI Home Datacenter Master Status

## Current Phase

Sprint 6 — Project Audit and Stabilization

## Mac mini M4 — Brain

- AI Agent
- OpenAI
- Claude
- Ollama
- Homepage
- WordPress
- n8n
- Notion
- GitHub
- Ubuntu Worker control
- Approval and notification workflow

Mac mini는 판단과 오케스트레이션을 담당한다.

## Ubuntu Server — Worker

- Docker
- Storage
- Backup
- Immich
- Nextcloud
- Plex
- Ubuntu Runtime
- Storage Agent
- Inventory
- SHA256 처리
- Freshness Audit
- Reconcile

Ubuntu에서는 AI 추론 워크로드를 실행하지 않는다.

## Current Storage State

- Schema v3 적용
- Runtime 명령 49개 자동 탐색 정상
- 기존 SHA256 보존
- Incremental Duplicate Backfill 비활성화
- 자동 삭제 비활성화
- exHDD1 삭제 상태 Inventory 반영 필요 또는 진행 중
- exHDD2 Reconcile 검증 진행 중
- Archive Immich / Nextcloud 후순위

## Current Safety Policy

- No automatic deletion
- Archive remains the master repository
- Existing SHA256 values are preserved
- Database backup is required before write operations
- Runtime databases and generated reports are excluded from Git
