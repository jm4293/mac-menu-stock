# StockBar — 맥 메뉴바 한국 주식/지수 표시 앱

코스피 지수와 삼성전자(005930) 시세를 맥 상단 메뉴바에 실시간으로 표시합니다.
데이터는 **LS증권 OpenAPI**를 사용합니다. (상승=빨강, 하락=파랑 / 한국식 색상)

## 1. 사전 준비

Xcode Command Line Tools(스위프트 컴파일러)가 필요합니다. 없으면 설치:

```bash
xcode-select --install
```

## 2. 빌드

이 폴더에서:

```bash
cd StockBar
chmod +x build.sh
./build.sh
```

성공하면 `build/StockBar.app` 이 생성됩니다.

## 3. API 키 설정

처음 한 번 앱을 실행하면 `~/.stockbar/config.json` 템플릿이 자동 생성됩니다.
또는 메뉴에서 **설정 파일 열기**를 누르면 바로 열립니다.

```json
{
  "appkey": "여기에_APP_KEY_입력",
  "appsecret": "여기에_APP_SECRET_입력",
  "refreshSeconds": 5,
  "showLabels": true,
  "useColor": true,
  "indices": ["001"],
  "stocks": ["005930"],
  "debug": false
}
```

LS증권에서 발급받은 키를 `appkey` / `appsecret` 에 넣고 저장하세요.

- `refreshSeconds`: 갱신 주기(초). 최소 2초.
- `showLabels`: 종목명 표시 여부. `false`면 숫자만 표시. (메뉴에서 토글 가능)
- `useColor`: 등락 색상(상승 빨강/하락 파랑) 사용 여부. (메뉴에서 토글 가능)
- `indices`: 업종코드 배열 (코스피 = `001`, 코스닥 = `301`)
- `stocks`: 종목코드 배열 (삼성전자 = `005930`). 메뉴 **종목 추가…/삭제**로도 관리 가능.
- `debug`: `true`면 메뉴에 **디버그 로그 보기**가 생겨 API 원본 응답을 확인할 수 있음.

> 메뉴(메뉴바 클릭): 지금 새로고침 · 종목 추가…/삭제 · 종목명 표시 토글 · 등락 색상 토글 · 설정 파일 열기.
> 메뉴가 열려 파란 하이라이트일 때는 글자가 자동으로 흰색이 되어 잘 보입니다.

저장 후 메뉴의 **설정 다시 불러오기**를 누르거나 앱을 재실행하면 적용됩니다.

> 키는 소스코드가 아니라 이 설정 파일에만 저장됩니다.

## 4. 실행

```bash
open build/StockBar.app
```

Dock 아이콘 없이 메뉴바에만 나타납니다. 예시:

```
코스피 2,580.12 ▲0.52%   삼성전자 71,200 ▲1.20%
```

메뉴(클릭 시): 상세 시세 · 마지막 갱신 시각 · 지금 새로고침 · 설정 파일 열기 · 종료

## 5. 응용프로그램에 설치 + 자동 실행(선택)

```bash
cp -R build/StockBar.app /Applications/
```

로그인 시 자동 실행하려면: **시스템 설정 → 일반 → 로그인 항목**에서 `+` 로 StockBar 추가.

## 참고: API 필드 검증

LS OpenAPI 응답의 정확한 필드명은 [개발자 콘솔(테스트베드)](https://openapi.ls-sec.co.kr/testbed-console)에서 확인할 수 있습니다.
만약 값이 0으로만 보이면 `main.swift` 의 `fetchStock` / `fetchIndex` 에서 사용하는
필드명(`price`, `jisu`, `diff`, `change`, `sign`)을 실제 응답에 맞춰 조정하세요.

- 토큰: `POST /oauth2/token`
- 주식 시세: `t1102` (`t1102InBlock.shcode`)
- 업종 시세: `t1511` (`t1511InBlock.upcode`)
