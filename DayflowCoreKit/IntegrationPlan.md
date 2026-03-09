# Integration Plan (의존성/코드 이관 가이드)

## 해야 할 일 (순서)
1) 의존성 추가  
   - GRDB (WAL 설정 지원)  
   - ScreenCaptureKit (macOS 13+)  
   - AVFoundation / CoreMedia (영상 처리)  
   - Combine/SwiftUI는 기존 프로젝트에 이미 포함됨

2) Dayflow Core 코드 이관 (원본 위치: `/Users/mk-mac-391/project/Dayflow/Dayflow/Core/...`)  
   - Recording: `ScreenRecorder.swift`, `ActiveDisplayTracker.swift`, `StorageManager.swift`, `TimelapseStorageManager.swift`, `StoragePreferences.swift`, `VideoProcessingService.swift`  
   - Analysis: `AnalysisManager.swift`  
   - AI: `LLMService.swift`, `LLMLogger.swift`, Providers (`GeminiDirectProvider.swift`, `OllamaProvider.swift`, `DayflowBackendProvider.swift` stub), prompt prefs/models as needed  
   - Models: `AnalysisModels.swift`, Timeline/Category 모델  
   - Utilities/System: 최소한 `AppState`, `KeychainManager`, `CategoryStore` 등 LLM/Storage에서 참조되는 것들

3) `DayflowEngine` 연결  
   - Storage: GRDB StorageManager를 basePath로 초기화 후 퍼사드가 참조  
   - Recording: `allowWrites == true`일 때 `ScreenRecorder` start/stop 연결  
   - Analysis: `AnalysisManager.startAnalysisJob/stopAnalysisJob` 연결, 타이머 60s  
   - LLM: `LLMService.processBatch`를 퍼사드/AnalysisManager에서 호출하도록 주입  
   - Timelapse: `AnalysisManager` 내 VideoProcessingService 호출 유지

4) 설정/플래그 노출  
   - Settings UI에 프로바이더(Gemini/Ollama/Backend), API 키/엔드포인트, 저장 경로, 녹화 토글(add `allowWrites`) 노출  
   - 기존 Dayflow 앱과의 충돌 방지: 단일 실행 보장 또는 별도 basePath 사용

5) 권한/빌드 설정  
   - Screen Recording 사용 설명(Info.plist) 및 entitlements 추가  
   - 타겟 macOS 13+ 확인

6) 안전 장치  
   - `allowWrites` 기본 false 유지  
   - DB 마이그레이션/쓰기 전에 백업 옵션 제공  
   - 동시 실행 감지(이미 열려 있으면 start 차단)

## 파일 이관 우선순위 (원본 → DayflowCoreKit/Source/...)
1) 스토리지/모델
   - Core/Recording/StorageManager.swift
   - Core/Recording/TimelapseStorageManager.swift
   - Core/Recording/StoragePreferences.swift
   - Models/AnalysisModels.swift, Timeline 관련 모델
2) 기록/비디오
   - Core/Recording/ScreenRecorder.swift
   - Core/Recording/ActiveDisplayTracker.swift
   - Core/Recording/VideoProcessingService.swift
3) 배치/파이프라인
   - Core/Analysis/AnalysisManager.swift
4) LLM/AI
   - Core/AI/LLMService.swift
   - Core/AI/LLMLogger.swift
   - Core/AI/GeminiDirectProvider.swift, OllamaProvider.swift, DayflowBackendProvider.swift, Gemini/Ollama prefs/models 유틸
5) 지원 유틸
   - System/AppState, KeychainManager, CategoryStore 등 상기 파일이 참조하는 최소 집합

## 미적용(앱 코드 반영 전) 문서/설계
- `SettingsHookExample.md`, `BridgeChecklist.md`: Settings → Config → Engine 연동 흐름
- `StartStopDesign.md`: start/stop 조건/의사코드

## 아직 남은 TODO (코드 단)
- 퍼사드 TODO 구현: StorageManager/Recorder/Analysis/LLM 연동
- No-Op Telemetry를 실제 로거나 완전 제거 결정
- UI 데이터 변환: StorageManager → `TimelineCardLite` 매핑 구현
