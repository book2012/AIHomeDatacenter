# Deferred Scripts

이 디렉터리는 향후 검토할 기능을 보존한다.

## 정책

- Ubuntu Runtime에서 자동 노출하지 않는다.
- 운영 스케줄러에 등록하지 않는다.
- 자동 실행하지 않는다.
- 운영 DB 또는 실제 파일을 변경하기 전에 별도 Preview와 승인 절차를 구현한다.
- 기능을 재개할 때 Architecture, Test, Git, Documentation 절차를 다시 따른다.

## 분류 기준

- 현재 운영 가능: scripts/commands
- 실험 및 성능 검증: scripts/experimental
- 향후 구현 또는 일시 보류: scripts/deferred
