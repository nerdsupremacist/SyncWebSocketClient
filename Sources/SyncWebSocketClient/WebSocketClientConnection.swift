
import Foundation
import Sync
import Combine

public class WebSocketClientConnection: ConsumerConnection {
    @Published
    public fileprivate(set) var isConnected: Bool = false

    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        return $isConnected.eraseToAnyPublisher()
    }

    private let taskCreator: WebSocketTaskCreator
    private let session: URLSession
    public let codingContext: EventCodingContext

    private var task: URLSessionWebSocketTask? = nil
    private let receivedDataSubject = PassthroughSubject<Data, Never>()
    private var listenTask: Task<Void, Error>? = nil
    private var delegate: Delegate? = nil

    init(taskCreator: WebSocketTaskCreator,
         session: URLSession,
         codingContext: EventCodingContext) {

        self.taskCreator = taskCreator
        self.session = session
        self.codingContext = codingContext
    }

    deinit {
        self.listenTask?.cancel()
    }

    private func listen(task: URLSessionWebSocketTask) {
        let sequence = WebSocketStream(task: task)
        listenTask = Task { [unowned self] in
            for try await data in sequence {
                self.receivedDataSubject.send(data)
            }
            isConnected = false
        }
    }

    public func connect() async throws -> Data {
        let delegate = Delegate(connection: self)
        let task = taskCreator.task(session: session)
        task.delegate = delegate
        let messageTask = Task {
            try await task.receive()
        }
        task.resume()
        isConnected = true
        let message = try await messageTask.value
        listen(task: task)
        self.task = task
        return message.data
    }

    public func disconnect() {
        delegate = nil
        task?.cancel()
        listenTask?.cancel()
        isConnected = false
    }

    public func send(data: Data) {
        task?.send(.data(data)) { _ in
            // ignore error for now
        }
    }

    public func receive() -> AnyPublisher<Data, Never> {
        return receivedDataSubject.eraseToAnyPublisher()
    }
}

extension WebSocketClientConnection {
    private class Delegate: NSObject, URLSessionWebSocketDelegate {
        private unowned let connection: WebSocketClientConnection

        init(connection: WebSocketClientConnection) {
            self.connection = connection
            super.init()
        }

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            guard let error = error as? URLError else { return }
            switch error.code {
            case .cancelled:
                break
            default:
                connection.disconnect()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error = error as? URLError else { return }
            switch error.code {
            case .cancelled:
                break
            default:
                connection.disconnect()
            }
        }

        func urlSession(_ session: URLSession,
                        webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                        reason: Data?) {

            connection.disconnect()
        }
    }
}

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

private class WebSocketStream: AsyncSequence {
    typealias Element = Data
    typealias AsyncIterator = WebSocketAsyncIterator

    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func makeAsyncIterator() -> AsyncIterator {
        return WebSocketAsyncIterator(task: task)
    }
}

private class WebSocketAsyncIterator: AsyncIteratorProtocol {
    typealias Element = Data

    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func next() async throws -> Data? {
        guard case .invalid = task.closeCode else { return nil }
        let message = try await task.receive()
        return message.data
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
