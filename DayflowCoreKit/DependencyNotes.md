# Dependency Notes (SPM 예시)

> 프로젝트 설정을 직접 수정하지 않고 참고용으로만 추가한 메모입니다.

## Swift Package Manager 예시
```swift
// Package.swift (예시)
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.25.0")
],
targets: [
    .target(
        name: "DayflowCoreKit",
        dependencies: [
            .product(name: "GRDB", package: "GRDB.swift")
        ]
    )
]
```

## 필수 프레임워크
- ScreenCaptureKit (macOS 13+)
- AVFoundation / CoreMedia
- Combine / SwiftUI (이미 기본 포함)

## 권한/설정 체크리스트
- Info.plist: 화면녹화 권한 설명 문자열
- Entitlements: Screen Recording 권한
- 타겟 macOS 13+ 확인

## 의존성 추가 시 주의
- GRDB는 Dayflow 원본과 동일한 메이저 버전 사용 권장.
- ScreenCaptureKit은 시뮬레이터 직접 캡처 불가(실기 테스트 필요).
