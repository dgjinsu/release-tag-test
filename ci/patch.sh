#!/usr/bin/env bash
# 테스트용 patch.sh. 실제 현장에서는
#   검증 → 폐쇄망 레지스트리 적재 → 안 바뀐 서비스 재태깅 → .env 태그 갱신 → N대 pull/up → 스모크 테스트 → 실패 시 롤백
# 까지 한다. 여기서는 해시 검증과 images.json 출력만 한다.
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/3] SHA256SUMS 검증"
sha256sum -c SHA256SUMS

echo "[2/3] 적용 대상 (images.json)"
if command -v jq >/dev/null 2>&1; then
  jq -r '.images[] | "  \(.name)  tag=\(.tag)  from=\(.from)  \(.digest)"' images.json
else
  cat images.json
fi

echo "[3/3] (실제 환경) 레지스트리 적재 → .env 태그 갱신 → docker compose pull && up -d → 스모크 테스트"
echo "done"
