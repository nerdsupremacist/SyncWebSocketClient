
import Foundation
import Sync
import Combine

@available(macOS 12.0, *)
public class WebSocketClientConnection: ConsumerConnection {
    public private(set) var isConnected: Bool = false

    private let session: URLSession
    public let codingContext: EventCodingContext

    private var task: URLSessionWebSocketTask? = nil
    private var asyncTask: Task<Void, Never>?
    private let receivedDataSubject = PassthroughSubject<Data, Never>()

    init(session: URLSession = .shared,
         codingContext: EventCodingContext = JSONEventCodingContext()) {

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
        let task = session.webSocketTask(with: URL(string: "")!)
        let messageTask = Task {
            try await task.receive()
        }
        task.resume()
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
