
import Foundation
import Sync
import OpenCombineShim
#if os(WASI)
import JavaScriptKit

extension ConsumerConnection where Self == WebSocketClientConnection {

    public static func webSocket(url: URL,
                                 codingContext: EventCodingContext = .json) -> ConsumerConnection {

        return WebSocketClientConnection(url: url, codingContext: codingContext)
    }

}

public class WebSocketClientConnection: ConsumerConnection {
    enum WebSocketError: Error {
        case connectionDroppedDuringConnection
        case invalidMessageFromWebSocketOnFirstMessage
    }

    private static let webSocketConstructor = JSObject.global.WebSocket.function!
    private static let textEncoder = JSObject.global.TextDecoder.function!.new("utf-8")

    @Published
    public fileprivate(set) var isConnected: Bool = false

    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        return $isConnected.eraseToAnyPublisher()
    }

    private let url: URL
    public let codingContext: EventCodingContext

    private var webSocketObject: JSObject?
    private let receivedDataSubject = PassthroughSubject<Data, Never>()

    public init(url: URL,
                codingContext: EventCodingContext) {

        self.url = url
        self.codingContext = codingContext
    }

    deinit {
        disconnect()
    }

    public func connect() async throws -> Data {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                return continuation.resume(throwing: WebSocketError.connectionDroppedDuringConnection)
            }

            var webSocketObject: JSObject? = nil
            var onOpen: JSClosure?
            onOpen = JSClosure { [weak self] _ in
                guard let self = self else {
                    return .undefined
                }

                if let onOpen = onOpen {
                    _ = self.webSocketObject?.removeEventListener!("open", onOpen)
                }

                onOpen = nil
                return .undefined
            }

            var onMessage: JSClosure?
            onMessage = JSClosure { [weak self] arguments in
                guard let self = self else { return .undefined }
                let event = arguments.first!.object!
                switch event["data"] {
                case .string(let dataString):
                    guard let data = String(dataString).data(using: .utf8) else { break }
                    self.receivedDataSubject.send(data)
                case .object(let object):
                    let dataString = Self.textEncoder.decode!(object).string;
                    guard let data = dataString?.data(using: .utf8) else { break }
                    self.receivedDataSubject.send(data)
                default:
                    break
                }
                return .undefined
            }

            var onFirstMessage: JSClosure? = nil
            onFirstMessage = JSClosure { arguments in
                let event = arguments.first!.object!
                switch event["data"] {
                case .string(let dataString):
                    guard let data = String(dataString).data(using: .utf8) else { break }
                    _ = webSocketObject?.removeEventListener!("message", onFirstMessage)
                    onFirstMessage = nil
                    _ = webSocketObject?.addEventListener!("message", onMessage)
                    continuation.resume(returning: data)
                    return .undefined
                default:
                    break
                }
                continuation.resume(throwing: WebSocketError.invalidMessageFromWebSocketOnFirstMessage)
                return .undefined
            }

            var onClose: JSClosure?
            onClose = JSClosure { [weak self] _ in
                if let listener = onFirstMessage {
                    _ = webSocketObject?.removeEventListener!("message", listener)
                    onFirstMessage = nil
                }
                if let listener = onMessage {
                    _ = webSocketObject?.removeEventListener!("message", listener)
                    onMessage = nil
                }
                _ = webSocketObject?.removeEventListener!("close", onClose)
                if let self = self {
                    self.isConnected = false
                }
                return .undefined
            }

            webSocketObject = Self.webSocketConstructor.new(self.url.absoluteString)
            self.webSocketObject = webSocketObject

            _ = webSocketObject?.addEventListener!("message", onFirstMessage)
            _ = webSocketObject?.addEventListener!("close", onClose)
            _ = webSocketObject?.addEventListener!("error", onClose)
            _ = webSocketObject?.addEventListener!("open", onOpen)
        }
    }

    public func disconnect() {
        guard isConnected else { return }
        _ = webSocketObject?.close!()
        isConnected = false
    }

    public func send(data: Data) {
        guard isConnected else { return }
        guard let message = String(data: data, encoding: .utf8) else { return }
        _ = webSocketObject?.send!(message)
    }

    public func receive() -> AnyPublisher<Data, Never> {
        return receivedDataSubject.eraseToAnyPublisher()
    }
}

#endif
