# release-tag-test

GitHub Release / Tag 흐름 테스트용 저장소. Docker 없이 `services/<svc>` 디렉터리를 tar 로 묶어 "이미지 tar" 를 흉내낸다.

## 규칙 한 줄

**브랜치 이름이 버전이다.** `release/1.1.0` 에 push 하면 `v1.1.0-rc.1`, `v1.1.0-rc.2` … 가 생기고, 승격하면 `v1.1.0` 이 된다.

- 브랜치 이름은 `release/<MAJOR.MINOR.PATCH>` 형식이어야 한다. 아니면 워크플로우가 에러로 멈춘다
- 이미 정식 릴리즈된 버전(`v1.1.0` 존재)의 브랜치에 다시 push 하면 멈춘다. 다음 패치는 새 브랜치 `release/1.1.1`
- rc 번호는 같은 버전 안에서 push 마다 1씩 올라간다. 덮어쓰지 않는다

## 구조

| 경로 | 역할 |
|---|---|
| `services/*/` | 서비스 흉내. 파일을 바꾸면 "그 서비스가 바뀐 것" |
| `ci/build.sh` | 바뀐 서비스만 tar 생성 + `images.json` + `SHA256SUMS` |
| `ci/patch.sh` | 현장 적용 스크립트 흉내 (해시 검증 + 목록 출력) |
| `.github/workflows/rc.yml` | 트리거 ①: `release/<버전>` push → `v<버전>-rc.N` Pre-release 자동 발행 |
| `.github/workflows/promote.yml` | 트리거 ②: Run workflow 버튼 → rc 를 재빌드 없이 `v<버전>` 정식으로 승격. `images.json` 의 `from` 을 따라 각 rc 의 tar 를 모아 **서비스 전체** 번들로 만든다 |

바뀐 서비스 판별 기준: 같은 버전의 직전 rc → 없으면 최신 정식 릴리즈 → 그것도 없으면 전체 빌드.

## 시나리오

### 0. 준비 (1회)

```bash
gh auth login
```

```bash
git add -A && git commit -m "release/tag test scaffold" && git push -u origin main
```

`main` push 로는 rc 가 생기지 않는다 (`release/` 브랜치가 아니므로).

### 1. 릴리즈 브랜치 push → rc.1 자동 발행

```bash
git checkout -b release/1.1.0 && git push -u origin release/1.1.0
```

- Actions 탭에서 `rc-release` 실행 확인 (1분 내). Summary 에 브랜치·비교 기준·빌드한 서비스가 표시됨
- Releases 에 `v1.1.0-rc.1` (Pre-release). 첨부: `limitsample-*.tar.gz`, `recipe-*.tar.gz`, `images.json`, `SHA256SUMS`, `patch.sh`
- 비교 기준이 없어 전체(2개) 빌드

### 2. 현장 실패 가정 → 수정 push → rc.2

```bash
echo "limitsample v2 (fix)" > services/limitsample/app.txt && git commit -am "fix: limitsample 운영 경로 규칙" && git push
```

- `v1.1.0-rc.2` 생성. 첨부에 **limitsample tar 만** 있고 recipe tar 는 없음
- `images.json` 에서 recipe 는 `"from": "v1.1.0-rc.1"` 로 직전 rc 를 가리킴
- rc.1 페이지는 그대로 남아 있음

### 3. 현장 다운로드 흉내

브라우저: repo → Releases → `v1.1.0-rc.2` → Assets 클릭. 또는

```bash
gh release download v1.1.0-rc.2 -D rc2 && (cd rc2 && bash patch.sh)
```

Windows 해시 검증 흉내: `certutil -hashfile rc2\images.json SHA256` 값을 `SHA256SUMS` 와 비교

### 4. 통과 → 승격 버튼

GitHub 웹 → Actions → 왼쪽 `promote` → 오른쪽 **Run workflow** → `rc` 에 `v1.1.0-rc.2` → Run.
(Use workflow from 은 `main` 그대로)

CLI 로도 가능:

```bash
gh workflow run promote -f rc=v1.1.0-rc.2
```

확인할 것:

- Releases 목록: `v1.1.0` **Latest** / `v1.1.0-rc.2` Pre-release / `v1.1.0-rc.1` Pre-release
- `v1.1.0` 의 태그가 rc.2 와 **같은 커밋** 을 가리킴 (Release 페이지의 commit 링크)
- 첨부에 **서비스 전체** tar 가 있음 (`limitsample-v1.1.0.tar.gz`, `recipe-v1.1.0.tar.gz`). rc.2 에는 recipe 만 있었지만 정식은 limitsample 을 rc.1 에서 가져와 채움
- 내용은 검증된 rc 파일 그대로. digest 가 rc.2 의 `images.json` 과 같은지:

```bash
gh release download v1.1.0 -D final && diff <(jq -r ".images[].digest" rc2/images.json) <(jq -r ".images[].digest" final/images.json) && echo SAME
```

### 5. 잘못된 승격 시도 (막히는지 확인)

```bash
gh workflow run promote -f rc=v1.1.0-rc.2
```

`v1.1.0 이 이미 존재합니다` 로 실패해야 한다. 정식 태그는 덮어쓰지 않는다.

### 6. 다음 패치 시작

```bash
git checkout -b release/1.1.1 && git push -u origin release/1.1.1
```

`v1.1.1-rc.1` 이 생긴다. 같은 버전의 rc 가 없으니 비교 기준은 최신 정식 `v1.1.0` 이 되고, 그 이후 바뀐 서비스가 없어 tar 없이 `images.json` 만 갱신된다. 이 상태에서 서비스를 고쳐 push 하면 그 서비스 tar 만 담긴 `v1.1.1-rc.2` 가 생긴다.

이미 릴리즈된 `release/1.1.0` 에 다시 push 하면 "이미 정식 릴리즈된 버전" 으로 멈춘다.

### 7. 정리 (선택)

```bash
gh release delete v1.1.0-rc.1 --cleanup-tag -y
```

정리는 **정식 승격 이후에만**. 승격이 각 rc 의 첨부를 모아 정식 번들을 만들기 때문에, 승격 전에 rc 첨부를 지우면 승격이 실패한다.

실패한 rc 의 파일만 지우려면 `gh release delete-asset v1.1.0-rc.1 <파일명> -y`.

## 실제 환경과 다른 점

| 테스트 | 실제 |
|---|---|
| `ubuntu-latest` GitHub 호스팅 러너 | `[self-hosted, nexus]` 사내 러너 (Nexus 접근 필요) |
| `tar czf services/<svc>` | `docker build` → Nexus push → `docker save` |
| `images.json` digest = tar 해시 | 레지스트리 이미지 digest |
| `patch.sh` 가 해시 검증만 | 레지스트리 적재 → `.env` 갱신 → N대 pull/up → 스모크 테스트 → 롤백 |
| 승격 시 Nexus 재태깅 없음 | `crane tag <image>@<digest> vX.Y.Z` 추가 |
