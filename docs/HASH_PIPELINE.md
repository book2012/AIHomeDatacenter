# AI Home Datacenter Hash Pipeline

## Role

Hash 작업은 Ubuntu Worker에서 실행한다.

Mac mini는 Hash 계산을 직접 수행하지 않고, Ubuntu Runtime을 통해 작업을 승인하고 결과를 분석한다.

## Processing Flow

Inventory
→ Pending Queue
→ Path Validation
→ Size Validation
→ SHA256 Dry Run
→ Database Apply Preview
→ Transaction Apply
→ Duplicate Incremental Update

## Current Safety Rules

- 기존 SHA256를 덮어쓰지 않는다.
- Immich와 Nextcloud는 현재 Hash 대상에서 제외한다.
- 파일 수와 총 처리 용량을 제한한다.
- 실제 경로와 DB 크기가 일치해야 한다.
- DB 반영 전에 Preview를 수행한다.
- SQLite 온라인 백업을 생성한다.
- DB 변경은 단일 Transaction으로 처리한다.
- 실패하면 전체 Rollback한다.
- 자동 파일 삭제는 허용하지 않는다.
- 사용자 승인 없이 정리 작업을 실행하지 않는다.

## Runtime Commands

    scripts/runtime.sh hash-audit
    scripts/runtime.sh hash-queue-preview
    scripts/runtime.sh hash-queue-validate
    scripts/runtime.sh hash-worker-dry-run
    scripts/runtime.sh hash-db-apply-preview
    scripts/runtime.sh hash-pilot-safe
    scripts/runtime.sh hash-rollback-test
    scripts/runtime.sh hash-backup-restore-test
    scripts/runtime.sh hash-batch-dry-run
    scripts/runtime.sh hash-batch-apply-preview

## Duplicate Engine Direction

전체 Inventory를 반복적으로 재계산하는 방식은 운영 방식으로 사용하지 않는다.

향후 Duplicate Engine은 신규 Hash 완료 파일만 처리하는 Incremental 방식으로 구현한다.

    New Hash
    → Existing SHA256 Lookup
    → Duplicate Group Update
    → Report
    → User Approval

## Deferred Work

- Batch ID 영속화
- hash_runs 스키마 강화
- Incremental Duplicate Index
- Retry 및 Resume 상태
- 운영 Batch 자동 테스트
- Mac mini 승인 인터페이스
