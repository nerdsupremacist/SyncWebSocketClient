
import Foundation
import Sync
import Combine

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public class WebSocketClientConnection: ConsumerConnection {
    public private(set) var isConnected: Bool = false

    private let taskCreator: WebSocketTaskCreator
    private let session: URLSession
    public let codingContext: EventCodingContext

    private var task: URLSessionWebSocketTask? = nil
    private var asyncTask: Task<Void, Never>?
    private let receivedDataSubject = PassthroughSubject<Data, Never>()

    init(taskCreator: WebSocketTaskCreator,
         session: URLSession,
         codingContext: EventCodingContext) {

        self.taskCreator = taskCreator
        self.session = session
        self.codingContext = codingContext
    }

    private func listen() {
        task?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print(error)
            case .success(let message):
                self?.receivedDataSubject.send(message.data)
            }
        }
    }

    public func connect() async throws -> Data {
        let task = taskCreator.task(session: session)
        let messageTask = Task {
            try await task.receive()
        }
        task.resume()
        isConnected = true
        let message = try await messageTask.value
        listen()
        self.task = task
        return message.data
    }

    public func disconnect() {
        task?.cancel()
    }

    public func send(data: Data) {
        task?.send(.data(data)) { error in
            print(error.debugDescription)
        }
    }

    public func receive() -> AnyPublisher<Data, Never> {
        return receivedDataSubject.eraseToAnyPublisher()
    }
}

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
extension WebSocketClientConnection {

    public convenience init(url: URL,
                session: URLSession = .shared,
                codingContext: EventCodingContext = JSONEventCodingContext()) {

        self.init(taskCreator: URLWebSocketTaskCreator(url: url), session: session, codingContext: codingContext)
    }

    public convenience init(url: URL,
                protocols: [String],
                session: URLSession = .shared,
                codingContext: EventCodingContext = JSONEventCodingContext()) {

        self.init(taskCreator: URLAndProtocolWebSocketTaskCreator(url: url, protocols: protocols), session: session, codingContext: codingContext)
    }

    public convenience init(request: URLRequest,
                            session: URLSession = .shared,
                            codingContext: EventCodingContext = JSONEventCodingContext()) {

        self.init(taskCreator: URLRequestTaskCreator(request: request), session: session, codingContext: codingContext)
    }

    public convenience init(request: WebSocketRequest,
                            session: URLSession = .shared,
                            codingContext: EventCodingContext = JSONEventCodingContext()) {

        self.init(taskCreator: WebSocketRequestTaskCreator(request: request), session: session, codingContext: codingContext)
    }

}

extension URLSessionWebSocketTask.Message {

    fileprivate var data: Data {
        switch self {
        case .data(let data):
            return data
        case .string(let string):
            return string.data(using: .utf8) ?? Data()
        @unknown default:
            fatalError()
        }
    }

}

protocol WebSocketTaskCreator {
    func task(session: URLSession) -> URLSessionWebSocketTask
}

private struct URLWebSocketTaskCreator: WebSocketTaskCreator {
    let url: URL

    func task(session: URLSession) -> URLSessionWebSocketTask {
        return session.webSocketTask(with: url)
    }
}

private struct URLAndProtocolWebSocketTaskCreator: WebSocketTaskCreator {
    let url: URL
    let protocols: [String]

    func task(session: URLSession) -> URLSessionWebSocketTask {
        return session.webSocketTask(with: url, protocols: protocols)
    }
}

private struct URLRequestTaskCreator: WebSocketTaskCreator {
    let request: URLRequest

    func task(session: URLSession) -> URLSessionWebSocketTask {
        return session.webSocketTask(with: request)
    }
}

public protocol WebSocketRequest {
    func request() -> URLRequest
}

private struct WebSocketRequestTaskCreator: WebSocketTaskCreator {
    let request: WebSocketRequest

    func task(session: URLSession) -> URLSessionWebSocketTask {
        return session.webSocketTask(with: request.request())
    }
}
