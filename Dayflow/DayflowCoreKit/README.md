# DayflowCoreKit (스캐폴드)

DayArc에 Dayflow 전체 기능(녹화 → 배치/LLM → 타임라인 저장)을 내재화하기 위한 모듈 초안입니다. **현재는 읽기 전용/부작용 없는 상태**이며, 기존 앱 코드를 수정하지 않습니다.

## 포함된 것
- `DayflowEngine.swift`: 퍼사드 + 설정 구조체. `allowWrites` 기본값은 `false`라 실수로 녹화/DB 쓰기가 시작되지 않습니다. 타임라인 조회는 TODO 상태.
- `NoOpTelemetry.swift`: Analytics/Sentry 더미 구현(네트워크 호출/파일 쓰기 없음).
- `ModuleNotes.md`: 향후 연결 방법과 위험 사항 정리.

## 다음 단계(연동 준비)
1) GRDB, ScreenCaptureKit, AVFoundation 의존성 추가 후 Dayflow Core 소스(Recording/Storage/Analysis/LLM/VideoProcessing) 투입.
2) `DayflowEngine` TODO 지점에서 실제 서비스 연결:
   - 저장 경로 주입 → StorageManager 초기화
   - `allowWrites == true`일 때만 ScreenRecorder 시작, AnalysisManager 타이머(60s) 시작
   - LLM 프로바이더/키 설정 주입
3) Settings에 프로바이더/키/저장 경로/녹화 토글 노출 → `DayflowCoreConfig`와 연동.
4) 기존 Dayflow 앱과 동시 쓰기 충돌 방지 정책 결정(단일 실행 보장 또는 별도 basePath 사용).

## 주의
- 이 폴더는 아직 빌드 타깃에 포함되지 않았습니다. 프로젝트 설정에서 명시적으로 추가해야 합니다.
- DB/파일 쓰기는 `allowWrites`가 true로 설정되고 실제 구현이 연결된 뒤에만 작동하도록 하십시오.
