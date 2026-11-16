import Foundation

/// One unit of a job: a single input, or every input of an operation that
/// combines its selection into one result.
public struct BatchItem: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case pending, running
        case succeeded([URL])
        /// The reason is ready to show to the user.
        case failed(String)
        /// Stopped while in flight, or never started because the job was cancelled.
        case cancelled
    }
    public let inputs: [URL]
    public var status: Status
    public init(inputs: [URL], status: Status = .pending) { self.inputs=inputs; self.status=status }
    public var outputs: [URL] { if case .succeeded(let urls)=status { return urls }; return [] }
    public var failure: String? { if case .failed(let reason)=status { return reason }; return nil }
}

public struct BatchReport: Sendable, Equatable {
    public let items: [BatchItem]
    public init(items: [BatchItem]) { self.items=items }
    public var outputs: [URL] { items.flatMap(\.outputs) }
    public var succeeded: Int { items.filter { !$0.outputs.isEmpty }.count }
    public var failed: Int { items.filter { $0.failure != nil }.count }
    public var cancelled: Int { items.filter { $0.status == .cancelled }.count }
    public var failedInputs: [URL] { items.filter { $0.failure != nil }.flatMap(\.inputs) }
    /// "7 of 9 done, 2 failed"
    public var summary: String {
        "\(succeeded) of \(items.count) done"+(failed>0 ? ", \(failed) failed":"")+(cancelled>0 ? ", \(cancelled) cancelled":"")
    }
}

public typealias BatchItemHandler = @Sendable (Int, BatchItem.Status) -> Void
