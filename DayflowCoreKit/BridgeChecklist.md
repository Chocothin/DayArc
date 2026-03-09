# Bridge Checklist (Settings → Engine, 코드 미적용)

## 입력 필드
- 저장 경로 (옵션)
- 프로바이더 선택 (Gemini / Ollama / Backend / Custom)
- API 키 / 엔드포인트
- 녹화 허용 토글 (`allowWrites`)

## 브리지 호출 순서
1) `DayflowConfigBridge.makeConfig(...)`로 설정 생성
2) `DayflowConfigBridge.applyConfig(...)`로 엔진에 적용 (side-effect 없음)
3) start/stop 정책 판단은 별도 함수에서 수행 (`StartStopDesign.md` 참고)

## 예시 흐름
```swift
let cfg = bridge.makeConfig(
    basePath: path,
    allowWrites: toggleValue,
    provider: selected.kind,
    apiKey: key,
    endpoint: endpoint
)
bridge.applyConfig(cfg)
maybeStartDayflow() // 조건부 시작 함수
```

## TODO (앱에서 구현 필요)
- UI 값 검증/에러 처리
- 권한/동시 실행 체크 후 start 호출 여부 결정
- 상태 표시(녹화 중/오프)와 사용자 알림
