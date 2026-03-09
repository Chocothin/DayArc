import Foundation

/// LLM 서비스 스탑게이트. 실제 Dayflow LLMService/프로바이더로 교체 예정.
public protocol LLMServicing {
    func processBatch(_ batchId: Int64, completion: @escaping (Result<Void, Error>) -> Void)
}

public final class LLMScaffold: LLMServicing {
    public init() {}
    public func processBatch(_ batchId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        // TODO: LLMService.processBatch 연결
        completion(.success(()))
    }
}
