# Module Notes (계획/위험)

## 설계 메모
- 퍼사드: `DayflowEngine`은 Config를 받아 녹화/분석/LLM/스토리지 전체를 감쌉니다.
- 경로: `basePath`를 주입해 기존 Dayflow 데이터 또는 별도 경로를 선택할 수 있어야 합니다.
- 플래그: `allowWrites`가 `true`일 때만 실제 녹화/DB 쓰기가 시작되도록 방어.
- Telemetry: 네트워크/로깅 의존을 제거하기 위해 No-Op Analytics/Sentry를 기본으로 사용.

## 아직 연결되지 않은 것들 (TODO)
- StorageManager (GRDB) 초기화 및 DB 마이그레이션
- ScreenRecorder/AnalysisManager 타이머 시작/중지
- LLMService + 프로바이더(Gemini/Ollama/Backend) 연결, 키 관리
- 타임라인/관측치/LLM 로그 조회 구현 (현재는 빈 배열 반환)
- Timelapse 생성(VideoProcessingService) 및 저장 한도 관리

## 위험/결정 필요
- 기존 Dayflow 앱과 동시 쓰기 충돌: 단일 실행 보장 또는 별도 basePath 필요
- 권한 UX: 화면녹화 권한 안내/문구/entitlement 적용
- 의존성: GRDB/ScreenCaptureKit/AVFoundation 버전 정합성, macOS 13+ 타겟 확인

## 제안 작업 순서
1) 의존성 추가(SPM 또는 벤더링) 후 Dayflow Core 소스 이동
2) DB 경로 주입 + StorageManager 초기화 → 읽기/쓰기 기능 연결
3) ScreenRecorder/AnalysisManager 연동 및 allowWrites 플래그 적용
4) Settings UI 연동(프로바이더/키/경로/녹화 토글) → Config 전달
5) 동시 실행 정책/스토리지 한도 정책 확정
