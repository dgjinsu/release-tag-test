#!/usr/bin/env bash
# 테스트용 빌드. 실제 환경에서는 docker build → Nexus push → docker save 가 들어가는 자리다.
# 여기서는 services/<svc> 디렉터리를 tar 로 묶어 "이미지 tar" 를 흉내낸다.
#
# 사용법: ci/build.sh <TAG> <PREV_IMAGES_JSON|-> [svc ...]
#   TAG              이번 rc 태그 (예: v1.12.1-rc.2)
#   PREV_IMAGES_JSON 직전 rc 의 images.json 경로. 없으면 "-"
#   svc ...          이번에 빌드할(바뀐) 서비스. 없으면 tar 를 만들지 않고 목록만 갱신
set -euo pipefail

TAG="$1"; PREV="$2"; shift 2
CHANGED=("$@")
ALL=$(ls services)
mkdir -p out

is_changed() { local s; for s in "${CHANGED[@]:-}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

for svc in "${CHANGED[@]:-}"; do
  [ -n "$svc" ] || continue
  tar czf "out/${svc}-${TAG}.tar.gz" -C services "$svc"
  echo "built out/${svc}-${TAG}.tar.gz"
done

# images.json: 서비스 전체 목록. 바뀐 것은 새 digest, 안 바뀐 것은 직전 rc 의 값을 그대로 가리킨다.
{
  echo "{"
  echo "  \"release\": \"${TAG}\","
  echo "  \"images\": ["
  first=1
  for svc in $ALL; do
    if is_changed "$svc"; then
      digest="sha256:$(sha256sum "out/${svc}-${TAG}.tar.gz" | cut -d' ' -f1)"
      from="$TAG"
    elif [ "$PREV" != "-" ] && [ -f "$PREV" ]; then
      digest=$(jq -r --arg s "$svc" '.images[] | select(.name==$s) | .digest' "$PREV")
      from=$(jq -r --arg s "$svc" '.images[] | select(.name==$s) | .from' "$PREV")
    else
      echo "ERROR: $svc 는 바뀌지 않았는데 직전 images.json 이 없습니다" >&2; exit 1
    fi
    [ $first = 1 ] || echo ","
    first=0
    printf '    { "name": "%s", "tag": "%s", "digest": "%s", "from": "%s" }' "$svc" "$TAG" "$digest" "$from"
  done
  echo
  echo "  ]"
  echo "}"
} > out/images.json

cp ci/patch.sh out/patch.sh
( cd out && sha256sum *.tar.gz images.json patch.sh > SHA256SUMS 2>/dev/null || sha256sum images.json patch.sh > SHA256SUMS )
echo "---- out/"; ls -la out
echo "---- images.json"; cat out/images.json
