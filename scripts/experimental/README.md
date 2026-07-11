# Experimental Scripts

이 디렉터리의 명령은 Ubuntu Runtime에서 자동 노출되지 않는다.

## 현재 실험 명령

- duplicate-table-preview.sh
- duplicate-rebuild-test.sh

## 분리 사유

전체 Inventory를 대상으로 하는 Duplicate 재계산은 대규모 데이터에서 실행 시간이 길다.

운영 Duplicate Engine은 다음 Incremental 방식을 사용한다.

    Newly completed hash
    → Existing duplicate lookup
    → Incremental group update
    → Processing state update

## 안전 정책

- 운영 DB에서 자동 실행하지 않는다.
- 실제 파일을 삭제하지 않는다.
- 테스트 또는 명시적인 수동 검증에만 사용한다.
