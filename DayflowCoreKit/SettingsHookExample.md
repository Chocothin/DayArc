# Settings Hook Example (설계 메모)

> 실제 앱 코드에는 영향을 주지 않는 참고용 문서입니다.

## 흐름 제안
1) Settings UI에서 입력받는 값
   - 저장 경로 선택(옵션) / 기본 경로 자동 선택
   - 프로바이더 선택(Gemini/Ollama/Backend/Custom)
   - API 키 / 엔드포인트
   - 녹화 허용 토글 (`allowWrites`)
2) 브리지 사용
```swift
let bridge = DayflowConfigBridge()
let cfg = bridge.makeConfig(
    basePath: selectedPath,
    allowWrites: recordingEnabled,
    provider: selectedProvider.kind,
    apiKey: apiKey,
    endpoint: endpointURL
)
bridge.applyConfig(cfg)
// start/stop은 호출 측 정책에 따라 분리
```
3) 시작/중지 정책 예시
   - `allowWrites == true`이고, 화면녹화 권한이 승인되어 있으며, 다른 Dayflow 인스턴스가 실행 중이 아닌 경우에만 `DayflowEngine.shared.start()`.
   - 앱 종료/일시정지 시 `DayflowEngine.shared.stop()`.

## 베스트 프랙티스
- 기본값은 `allowWrites=false` 유지.
- 키·경로 변경 시 즉시 `configure`, start/stop은 사용자가 명시적 토글로 수행.
- 동시 실행 방지 로직(이미 Dayflow 실행 감지) 추가 권장.
