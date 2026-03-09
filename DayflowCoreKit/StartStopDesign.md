# Start/Stop Design (정책 초안, 코드 미반영)

## 정책 옵션
- **조건부 시작**: `allowWrites == true` && 화면녹화 권한 승인 && 다른 Dayflow 인스턴스 미실행 ⇒ `start()`.
- **안전 중지**: 앱 종료/일시정지/권한 철회 시 `stop()`.
- **경합 방지**: 별도 락/파일 플래그로 동시 실행 감지.

## 의사코드 예시 (앱 코드에 붙일 때 참고)
```swift
func maybeStartDayflow() {
    guard config.allowWrites else { return }
    guard ScreenRecordingPermission.isGranted else { return }
    guard !OtherInstanceChecker.isRunning else { return }
    DayflowEngine.shared.start()
}

func stopDayflow() {
    DayflowEngine.shared.stop()
}
```

## 상태 흐름
- Settings 변경 → `DayflowConfigBridge`로 `configure` (side-effect 없음)
- 사용자/앱 이벤트로 `start/stop` 호출 → `allowWrites` 가드 후 Recorder/Analysis 시작/정지

## TODO (앱에서 구현 필요)
- 권한 체크 유틸(ScreenCaptureKit)
- 동시 실행 감지(예: PID/lock 파일)
- 에러/권한 거부 UI 안내
