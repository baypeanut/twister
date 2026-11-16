import Foundation
import Combine
import TwisterCore

@MainActor final class ToolSetupModel: ObservableObject {
    typealias Install = (ToolGroup, CancellationToken, @escaping @Sendable (Double?, String) -> Void) async throws -> Void
    private static let prompt = "Download the missing tools to enable all conversions and previews. Tools already found on your computer are kept."
    @Published private(set) var status: ToolSetupStatus
    @Published private(set) var reports: [ToolGroup: ToolGroupReport] = [:]
    @Published private(set) var sizes: [ToolGroup: Int64] = [:]
    @Published private(set) var working = false
    @Published private(set) var fraction: Double?
    @Published private(set) var message: String
    private let probe: () -> ToolSetupStatus
    private let installer: Install
    private let inspect: (ToolGroup) -> ToolGroupReport?
    private let measure: @Sendable (ToolGroup) -> Int64
    private let remover: (ToolGroup) throws -> Void
    private var task: Task<Void, Never>?
    private var token = CancellationToken()
    var onWorkingChange: (Bool) -> Void = { _ in }
    /// A conversion in progress keeps its tools.
    var isBusy: () -> Bool = { false }
    init(probe: @escaping () -> ToolSetupStatus = { ExternalToolSetup.status }, install: @escaping Install = { group, token, report in
        try await ExternalToolSetup.install(group, token: token, progress: report)
    }, inspect: @escaping (ToolGroup) -> ToolGroupReport? = { ExternalToolSetup.report($0) },
         measure: @escaping @Sendable (ToolGroup) -> Int64 = { ExternalToolSetup.installedSize($0) },
         remove: @escaping (ToolGroup) throws -> Void = { try ExternalToolSetup.remove($0) }) {
        self.probe = probe; self.installer = install; self.inspect = inspect; self.measure = measure; self.remover = remove
        let initial = probe(); status = initial
        message = initial.ready ? "Ready. You can go back to your files." : Self.prompt
        describe()
    }
    func refresh() {
        guard !working else { return }
        let previouslyReady = status.ready; status = probe(); describe()
        if status.ready { message = "Ready. You can go back to your files." }
        else if previouslyReady { message = Self.prompt }
    }
    /// Source, version and size of each group; sizes are read off the main thread.
    private func describe() {
        var found: [ToolGroup: ToolGroupReport] = [:]
        for group in ToolGroup.allCases { found[group] = inspect(group) }
        reports = found
        let removable = ToolGroup.allCases.filter { found[$0]?.removable == true }, measure = measure
        sizes = sizes.filter { removable.contains($0.key) }
        guard !removable.isEmpty else { return }
        Task { [weak self] in
            let measured = await Task.detached { Dictionary(uniqueKeysWithValues: removable.map { ($0, measure($0)) }) }.value
            self?.sizes = measured.filter { $0.value > 0 }
        }
    }
    /// Without a group, installs what conversions need; the optional Web group is installed only by name.
    func install(_ group: ToolGroup? = nil) {
        refresh(); install(groups: group.map { [$0] } ?? status.missing)
    }
    func install(groups requested: [ToolGroup]) {
        guard !working else { return }
        refresh()
        let groups = ToolGroup.allCases.filter { requested.contains($0) && !status.isReady($0) }
        guard !groups.isEmpty else { return }
        working = true; fraction = nil; token = CancellationToken(); onWorkingChange(true)
        let currentToken = token
        task = Task {
            defer { status = probe(); working = false; describe(); onWorkingChange(false); task = nil; NotificationCenter.default.post(name:.toolSetupChanged,object:nil) }
            do {
                for (index, item) in groups.enumerated() {
                    try currentToken.check(); try Task.checkCancellation()
                    let report: @Sendable (Double?, String) -> Void = { [weak self] value, label in
                        Task { @MainActor in
                            guard let self, self.working, !currentToken.isCancelled else { return }
                            self.fraction = value.map { (Double(index) + $0) / Double(groups.count) }; self.message = label
                        }
                    }
                    try await installer(item, currentToken, report)
                    status = probe()
                }
                let result = probe()
                guard groups.allSatisfy({ result.isReady($0) }) else {
                    throw TwisterError.failed("The downloaded tools are incomplete. Please try setup again.")
                }
                message = result.ready ? "Ready. You can go back to your files." : "One tool group is ready. Download the remaining tools to finish setup."
                fraction = 1
            } catch {
                message = currentToken.isCancelled || error is CancellationError ? "Setup cancelled. Existing tools were kept." : error.localizedDescription
            }
        }
    }
    /// Deletes only what setup installed for the group.
    func remove(_ group: ToolGroup) {
        guard !working else { return }
        guard !isBusy() else { message = "Wait for the current task to finish, then remove the tools."; return }
        do {
            try remover(group)
            // The Web downloads setting follows the installed tools again.
            if group == .web { UserDefaults.standard.removeObject(forKey: WebDownloadGate.preferenceKey) }
            status = probe(); describe()
            message = status.isReady(group) ? "The downloaded copy was removed. A copy found elsewhere on your computer is still used." : "The tools were removed. You can download them again at any time."
        } catch { message = error.localizedDescription }
        NotificationCenter.default.post(name:.toolSetupChanged,object:nil)
    }
    func cancel() { token.cancel(); task?.cancel() }
}
