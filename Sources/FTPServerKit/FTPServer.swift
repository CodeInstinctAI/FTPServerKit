//
//  FTPServer.swift
//  FTPServerKit
//
//  Created by Marc Janga on 11/11/2025.
//

import Combine
import Foundation
import Network
import os

/// Errors from starting an ``FTPServer``.
public enum FTPServerError: Error, LocalizedError {
    case alreadyStarted
    case stoppedBeforeReady
    case listenerFailed(any Error)

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            "The FTP server is already started."
        case .stoppedBeforeReady:
            "The FTP server was stopped before it finished starting."
        case .listenerFailed(let error):
            "The FTP server couldn't listen for connections: \(error.localizedDescription)"
        }
    }
}

/// A lightweight, read-only FTP server built on Network.framework.
///
/// Serves the files of an ``FTPFileProvider``. Supports USER, PASS, PWD, CWD, CDUP, TYPE, MODE, STRU,
/// PASV, EPSV, LIST, NLST, RETR, SIZE, MDTM, REST, ABOR, SYST, FEAT, OPTS, NOOP and QUIT.
public final class FTPServer: @unchecked Sendable {
    // Unchecked: the mutable state below is only touched on `queue`, except `storedDelegate` and
    // `eventContinuations`, which `observersLock` guards. `eventSubject` is only sent to on `queue`.

    public let configuration: FTPServerConfiguration

    let queue = DispatchQueue(label: "FTPServerKit.FTPServer")
    private let queueKey = DispatchSpecificKey<Void>()
    private let logger = Logger(subsystem: "FTPServerKit", category: "FTPServer")

    private enum State {
        case stopped, starting, running
    }

    private var state = State.stopped
    private var listener: NWListener?
    private var pendingStart: (@Sendable (Result<UInt16, any Error>) -> Void)?
    private var boundPort: UInt16?
    private var sessions: [UUID: FTPSession] = [:]
    /// Read by sessions on `queue`; use ``fileProvider`` from outside.
    private(set) var currentFileProvider: any FTPFileProvider

    private let observersLock = NSLock()
    private weak var storedDelegate: (any FTPServerDelegate)?
    private var eventContinuations: [UUID: AsyncStream<FTPServerEvent>.Continuation] = [:]
    private let eventSubject = PassthroughSubject<FTPServerEvent, Never>()

    // MARK: - Initialization

    public init(configuration: FTPServerConfiguration, fileProvider: any FTPFileProvider) {
        self.configuration = configuration
        self.currentFileProvider = fileProvider
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        let listener = listener
        let sessions = Array(sessions.values)
        eventContinuations.values.forEach { $0.finish() }
        eventSubject.send(completion: .finished)
        queue.async {
            listener?.cancel()
            sessions.forEach { $0.close() }
        }
    }

    // MARK: - Public API

    /// Receives server events on the main actor. Held weakly.
    public var delegate: (any FTPServerDelegate)? {
        get {
            observersLock.lock()
            defer { observersLock.unlock() }
            return storedDelegate
        }
        set {
            observersLock.lock()
            defer { observersLock.unlock() }
            storedDelegate = newValue
        }
    }

    /// A new stream of the server's events, in order, from the moment you read this property.
    ///
    /// Every read returns a separate stream, so several observers can follow the server at once,
    /// alongside the ``delegate``. The stream lasts across restarts and finishes when the server
    /// is deallocated; cancel the iterating task to stop listening earlier.
    ///
    /// ```swift
    /// .task {
    ///     for await event in server.events {
    ///         if case .receivedCommand(let command, let argument) = event { … }
    ///     }
    /// }
    /// ```
    public var events: AsyncStream<FTPServerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: FTPServerEvent.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.removeEventContinuation(id)
        }
        observersLock.lock()
        defer { observersLock.unlock() }
        eventContinuations[id] = continuation
        return stream
    }

    /// The server's events as a Combine publisher, for code built on Combine. Prefer ``events`` in new code.
    ///
    /// Subscribers only get events sent after they subscribe. The publisher lasts across restarts and
    /// finishes when the server is deallocated. Events arrive on the server's internal queue, so
    /// receive them on the main queue before updating UI:
    ///
    /// ```swift
    /// server.eventPublisher
    ///     .receive(on: DispatchQueue.main)
    ///     .sink { event in … }
    ///     .store(in: &cancellables)
    /// ```
    public var eventPublisher: AnyPublisher<FTPServerEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    /// The files the server serves. Can be replaced while the server runs; the next command uses the new provider.
    public var fileProvider: any FTPFileProvider {
        get { onQueue { currentFileProvider } }
        set { onQueue { currentFileProvider = newValue } }
    }

    /// Whether the server is listening for clients.
    public var isRunning: Bool {
        onQueue { state == .running }
    }

    /// The port the server listens on while it runs.
    public var port: UInt16? {
        onQueue { boundPort }
    }

    /// Starts listening and returns once clients can connect.
    /// - Returns: The port the server listens on.
    /// - Throws: ``FTPServerError``, for example when the port is already in use.
    @discardableResult
    public func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            start { continuation.resume(with: $0) }
        }
    }

    /// Starts listening and calls `completion`, on an internal queue, once clients can connect or starting failed.
    public func start(completion: @escaping @Sendable (Result<UInt16, any Error>) -> Void) {
        queue.async { [self] in
            guard state == .stopped else {
                completion(.failure(FTPServerError.alreadyStarted))
                return
            }

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            if configuration.bindsToLoopbackOnly {
                parameters.requiredInterfaceType = .loopback
            }

            let listener: NWListener
            do {
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: configuration.port) ?? .any)
            } catch {
                log(.error, "Couldn't create listener: \(error)")
                completion(.failure(FTPServerError.listenerFailed(error)))
                return
            }

            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                guard let self, let listener else { return }
                self.listener(listener, didChangeState: newState)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            state = .starting
            pendingStart = completion
            self.listener = listener
            listener.start(queue: queue)
        }
    }

    /// Disconnects every client and stops listening.
    public func stop() {
        onQueue {
            guard state != .stopped else { return }
            let wasRunning = state == .running
            tearDown()
            completeStart(with: .failure(FTPServerError.stoppedBeforeReady))
            log(.info, "Server stopped")
            if wasRunning {
                emit(.stopped(error: nil))
            }
        }
    }

    // MARK: - Listener

    private func listener(_ listener: NWListener, didChangeState newState: NWListener.State) {
        guard listener === self.listener else { return }

        switch newState {
        case .ready:
            guard state == .starting else { return }
            let port = listener.port?.rawValue ?? configuration.port
            boundPort = port
            state = .running
            log(.info, "Server listening on port \(port)")
            completeStart(with: .success(port))
            emit(.started(port: port))

        case .waiting(let error):
            log(.warning, "Listener waiting: \(error)")

        case .failed(let error):
            let wasRunning = state == .running
            log(.error, "Listener failed: \(error)")
            tearDown()
            completeStart(with: .failure(FTPServerError.listenerFailed(error)))
            if wasRunning {
                emit(.stopped(error: error))
            }

        default:
            break
        }
    }

    private func completeStart(with result: Result<UInt16, any Error>) {
        guard let pendingStart else { return }
        self.pendingStart = nil
        pendingStart(result)
    }

    private func tearDown() {
        listener?.cancel()
        listener = nil
        let closing = sessions.values
        sessions.removeAll()
        closing.forEach { $0.close() }
        boundPort = nil
        state = .stopped
    }

    // MARK: - Connection Handling

    private func accept(_ connection: NWConnection) {
        guard sessions.count < configuration.maximumConnections else {
            log(.warning, "Refused \(connection.endpoint): too many connections")
            connection.start(queue: queue)
            connection.send(
                content: Data("421 Too many connections, try again later\r\n".utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )
            return
        }

        let session = FTPSession(connection: connection, server: self, configuration: configuration, queue: queue)
        session.onClose = { [weak self] session in
            self?.sessions[session.id] = nil
        }
        sessions[session.id] = session
        log(.info, "Client connected from \(connection.endpoint)", connectionID: session.id)
        session.start()
    }

    // MARK: - Logging and Events

    func log(_ level: FTPLogEntry.Level, _ message: String, connectionID: UUID? = nil) {
        let entry = FTPLogEntry(date: Date(), level: level, connectionID: connectionID, message: message)
        logger.log(level: level.osLogType, "\(entry.description, privacy: .public)")
        configuration.logHandler?(entry)
    }

    /// Sends `event` to every ``events`` stream, to ``eventPublisher``, and to the delegate on the main actor.
    func emit(_ event: FTPServerEvent) {
        observersLock.lock()
        let delegate = storedDelegate
        let continuations = Array(eventContinuations.values)
        observersLock.unlock()

        continuations.forEach { $0.yield(event) }
        eventSubject.send(event)
        guard let delegate else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                event.deliver(to: delegate, from: self)
            }
        }
    }

    private func removeEventContinuation(_ id: UUID) {
        observersLock.lock()
        defer { observersLock.unlock() }
        eventContinuations[id] = nil
    }

    /// Runs `work` on `queue`, also when already on it.
    private func onQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try work()
        }
        return try queue.sync(execute: work)
    }
}

private extension FTPLogEntry.Level {
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
