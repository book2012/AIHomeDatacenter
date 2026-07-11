# Storage Agent

## 역할

Storage Agent는 Ubuntu Worker에서 Storage Inventory와 상태 검증을 담당한다.

Mac mini는 AI 판단과 승인만 담당하며, 실제 Storage 작업은 Ubuntu Runtime 명령을 통해 수행한다.

## 현재 기능

- SQLite Inventory
- Metadata Scan
- Scan Run 이력
- Missing 상태 관리
- SHA256 상태 관리
- Hash Queue Preview
- Hash Dry Run 및 Apply Preview
- SQLite Backup / Rollback 검증
- Storage Freshness Audit
- Storage Reconcile
- Incremental Duplicate Schema v3
- Incremental Duplicate Queue Preview

## Runtime 구조

`scripts/runtime.sh`는 `scripts/commands/*.sh` 파일을 자동 탐색한다.

현재 Runtime 명령 수와 Command 파일 수는 각각 49개이며 서로 일치한다.

## Schema v3

추가 객체:

- `hash_batches`
- `duplicate_processing`
- Incremental Duplicate 관련 인덱스

기존 `files` 테이블과 기존 SHA256 값은 보존한다.

## Storage 상태

### exHDD1

대부분의 파일이 사용자의 명시적 작업으로 삭제되었다.

Inventory 레코드는 삭제하지 않고 `is_missing` 상태로 보존한다.

### exHDD2

실제 파일 수와 Inventory 수가 달라 Reconcile 대상이다.

### Archive

`/mnt/storage` 파일시스템 아래에 존재한다.

현재 Inventory는 Immich와 Nextcloud 데이터로 구성되어 있으며 두 서비스 영역은 후순위로 유지한다.

Archive 일반 영역은 별도 Freshness 검증 후 Scan 여부를 결정한다.

## 안전 정책

- 자동 파일 삭제 금지
- 기존 SHA256 덮어쓰기 금지
- DB 쓰기 전 SQLite 온라인 백업
- DB 변경은 Transaction 사용
- 실패 시 Rollback
- 마운트 검증 없이 Missing 일괄 갱신 금지
- 대량 삭제 후 Freshness Audit 및 Reconcile 필수
- Immich와 Nextcloud는 현재 Hash 및 Duplicate 처리에서 제외

## Incremental Duplicate Test Suite

Incremental Duplicate 기능은 운영 DB 복사본에서 검증한다.

검증 항목:

- Processing 상태 전이
- Hash Batch 연결
- Duplicate Group 생성 및 재사용
- Retry 및 Resume
- 최대 재시도 한도
- Foreign Key 검사
- SQLite 무결성 검사
- 운영 DB 비변경

Retry 정책:

- 최대 자동 재시도 횟수는 3회이다.
- 한도에 도달하면 `failed` 상태를 유지한다.
- 이후 처리는 사용자 또는 Mac mini Brain의 승인이 필요하다.
- 자동 파일 삭제는 허용하지 않는다.

## Release Candidate Status

Storage Agent v1.0.0 RC1 passed the Release Candidate Audit.

Validated:

- Runtime command discovery
- Schema v3
- Database integrity
- Foreign key relationships
- Incremental Duplicate processing
- Retry and Resume
- Maximum Retry Count
- Operating database protection

Production Incremental Duplicate processing remains disabled until a real approved data queue exists.
