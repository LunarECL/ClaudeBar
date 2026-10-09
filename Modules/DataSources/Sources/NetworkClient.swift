import Foundation
import Mockable
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Mockable
public protocol NetworkClient: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse)
}
