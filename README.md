# release-tag-test

GitHub Release / Tag 흐름 테스트용 저장소. Docker 없이 `services/<svc>` 디렉터리를 tar 로 묶어 "이미지 tar" 를 흉내낸다.

## 구조

| 경로 | 역할 |
|---|---|
| `VERSION` | 이번 패치 버전 (`1.12.1`). CI 가 읽어 태그 이름을 만든다 |
| `services/*/` | 서비스 흉내. 파일을 바꾸면 "그 서비스가 바뀐 것" |
| `ci/build.sh` | 바뀐 서비스만 tar 생성 + `images.json` + `SHA256SUMS` |
| `ci/patch.sh` | 현장 적용 스크립트 흉내 (해시 검증 + 목록 출력) |
| `.github/workflows/rc.yml` | 트리거 ①: `release/**` push → `vX.Y.Z-rc.N` Pre-release 자동 발행 |
| `.github/workflows/promote.yml` | 트리거 ②: Run workflow 버튼 → rc 를 재빌드 없이 `vX.Y.Z` 정식으로 승격 + 배포 기록 |

## 시나리오

### 0. 준비 (1회)

```bash
gh auth login
```

```bash
git add -A && git commit -m "release/tag test scaffold" && git push -u origin main
```

### 1. 릴리즈 브랜치 push → rc.1 자동 발행

```bash
git checkout -b release/1.12 && git push -u origin release/1.12
```

- Actions 탭에서 `rc-release` 실행 확인 (1분 내)
- Releases 에 `v1.12.1-rc.1` (Pre-release) 생성. 첨부: `limitsample-*.tar.gz`, `recipe-*.tar.gz`, `images.json`, `SHA256SUMS`, `patch.sh`
- 직전 rc 가 없어 전체(2개) 빌드

### 2. 현장 실패 가정 → 수정 push → rc.2

```bash
echo "limitsample v2 (fix)" > services/limitsample/app.txt && git commit -am "fix: limitsample 운영 경로 규칙" && git push
```

- `v1.12.1-rc.2` 생성. 첨부에 **limitsample tar 만** 있고 recipe tar 는 없음
- `images.json` 을 열면 recipe 는 `"from": "v1.12.1-rc.1"` 로 직전 rc 를 가리킴
- rc.1 페이지는 그대로 남아 있음 (덮어쓰지 않음)

### 3. 현장 다운로드 흉내

브라우저: repo → Releases → `v1.12.1-rc.2` → Assets 클릭. 또는

```bash
gh release download v1.12.1-rc.2 -D rc2 && (cd rc2 && bash patch.sh)
```

Windows 해시 검증 흉내: `certutil -hashfile rc2\images.json SHA256` 값을 `SHA256SUMS` 와 비교

### 4. 통과 → 승격 버튼

GitHub 웹 → Actions → 왼쪽 `promote` → 오른쪽 **Run workflow** → `rc` 에 `v1.12.1-rc.2`, `site` 는 `A` → Run.
(Use workflow from 은 `main` 그대로)

CLI 로도 가능:

```bash
gh workflow run promote -f rc=v1.12.1-rc.2 -f site=A
```

확인할 것:

- Releases 목록: `v1.12.1` **Latest** / `v1.12.1-rc.2` Pre-release / `v1.12.1-rc.1` Pre-release
- `v1.12.1` 의 태그가 rc.2 와 **같은 커밋** 을 가리킴 (Release 페이지의 commit 링크)
- repo 우측 **Environments** 에 `site-A` 가 생기고 `v1.12.1` 배포 기록이 남음
- 첨부 파일이 rc.2 와 바이트 동일:

```bash
gh release download v1.12.1 -D final && diff final/SHA256SUMS rc2/SHA256SUMS && echo SAME
```

### 5. 잘못된 승격 시도 (막히는지 확인)

```bash
gh workflow run promote -f rc=v1.12.1-rc.2 -f site=B
```

`v1.12.1 이 이미 존재합니다` 로 실패해야 한다. 정식 태그는 덮어쓰지 않는다.

### 6. 다음 패치 시작

```bash
echo 1.12.2 > VERSION && git commit -am "1.12.2 시작" && git push
```

`v1.12.2-rc.1` 이 생기고, 직전 rc(`v1.12.1-rc.2`) 대비 바뀐 서비스가 없어 tar 없이 `images.json` 만 갱신된다.

### 7. 정리 (선택)

```bash
gh release delete v1.12.1-rc.1 --cleanup-tag -y
```

실패한 rc 의 파일만 지우려면 `gh release delete-asset v1.12.1-rc.1 <파일명> -y`.

## 실제 환경과 다른 점

| 테스트 | 실제 |
|---|---|
| `ubuntu-latest` GitHub 호스팅 러너 | `[self-hosted, nexus]` 사내 러너 (Nexus 접근 필요) |
| `tar czf services/<svc>` | `docker build` → Nexus push → `docker save` |
| `images.json` digest = tar 해시 | 레지스트리 이미지 digest |
| `patch.sh` 가 해시 검증만 | 레지스트리 적재 → `.env` 갱신 → N대 pull/up → 스모크 테스트 → 롤백 |
| 승격 시 Nexus 재태깅 없음 | `crane tag <image>@<digest> vX.Y.Z` 추가 |
