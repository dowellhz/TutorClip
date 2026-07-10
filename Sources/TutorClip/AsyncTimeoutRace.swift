import Foundation

enum AsyncTimeoutOutcome<Value> {
    case value(Value)
    case timedOut
    case cancelled
}

enum AsyncTimeoutRace {
    static func run<Value>(
        timeoutNanoseconds: UInt64,
        operation: @escaping () async -> Value
    ) async -> AsyncTimeoutOutcome<Value> {
        let cancellation = AsyncTimeoutCancellationBox<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let state = AsyncTimeoutRaceState(continuation: continuation)
                cancellation.install(state)
                let operationTask = Task {
                    let value = await operation()
                    state.resolve(.value(value))
                }
                state.registerOperationTask(operationTask)

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    state.resolve(.timedOut)
                }
                state.registerTimeoutTask(timeoutTask)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class AsyncTimeoutCancellationBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: AsyncTimeoutRaceState<Value>?
    private var wasCancelled = false

    func install(_ state: AsyncTimeoutRaceState<Value>) {
        lock.lock()
        self.state = state
        let shouldCancel = wasCancelled
        lock.unlock()
        if shouldCancel {
            state.resolve(.cancelled)
        }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let currentState = state
        lock.unlock()
        currentState?.resolve(.cancelled)
    }
}

private final class AsyncTimeoutRaceState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AsyncTimeoutOutcome<Value>, Never>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<AsyncTimeoutOutcome<Value>, Never>) {
        self.continuation = continuation
    }

    func registerOperationTask(_ task: Task<Void, Never>) {
        register(task, asOperation: true)
    }

    func registerTimeoutTask(_ task: Task<Void, Never>) {
        register(task, asOperation: false)
    }

    func resolve(_ outcome: AsyncTimeoutOutcome<Value>) {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        let operation = operationTask
        let timeout = timeoutTask
        operationTask = nil
        timeoutTask = nil
        lock.unlock()

        guard let pendingContinuation else { return }
        operation?.cancel()
        timeout?.cancel()
        pendingContinuation.resume(returning: outcome)
    }

    private func register(_ task: Task<Void, Never>, asOperation: Bool) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            task.cancel()
            return
        }
        if asOperation {
            operationTask = task
        } else {
            timeoutTask = task
        }
        lock.unlock()
    }
}
