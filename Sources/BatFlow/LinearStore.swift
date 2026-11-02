import Foundation
import SwiftUI

struct LinearIssue: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let url: URL?
    let priority: Int
    let stateName: String
    let stateType: String
    let stateColorHex: String

    var group: LinearGroup {
        if stateType == "unstarted" { return .todo }
        // "In Review" is a `started` state like "In Progress"; only the name tells them apart.
        if stateName.localizedCaseInsensitiveContains("review") { return .inReview }
        return .inProgress
    }
}

/// Active work first: Todo is usually the longest list and would push the rest out of view.
enum LinearGroup: String, CaseIterable, Identifiable {
    case inProgress = "In Progress"
    case inReview = "In Review"
    case todo = "Todo"

    var id: String { rawValue }
}

/// Pulls the viewer's assigned Todo / In Progress / In Review issues through the
/// `linear` CLI, which already holds the user's credentials.
@MainActor
final class LinearStore: ObservableObject {
    static let shared = LinearStore()

    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case cliMissing
        case failed(String)
    }

    @Published private(set) var issues: [LinearIssue] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    static let refreshInterval: TimeInterval = 60

    func refreshIfStale() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.refreshInterval { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if issues.isEmpty { status = .loading }

        guard let cli = Self.locateCLI() else {
            status = .cliMissing
            return
        }

        let result = await Task.detached(priority: .utility) {
            Self.runQuery(cli: cli)
        }.value

        switch result {
        case .success(let fetched):
            issues = fetched
            status = .loaded
            lastUpdated = Date()
        case .failure(let error):
            status = .failed(error.message)
        }
    }

    func issues(in group: LinearGroup) -> [LinearIssue] {
        issues.filter { $0.group == group }
    }

    // MARK: - CLI

    struct CLIError: Error {
        let message: String
    }

    nonisolated private static let query = """
    { viewer { assignedIssues(first: 100, orderBy: updatedAt, \
    filter: { state: { type: { in: ["unstarted", "started"] } } }) \
    { nodes { identifier title url priority state { name type color } } } } }
    """

    /// GUI apps don't inherit the shell PATH, so look in the usual install spots.
    nonisolated static func locateCLI() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/linear",
            "/usr/local/bin/linear",
            "\(home)/.local/bin/linear",
            "\(home)/.deno/bin/linear",
            "\(home)/.bun/bin/linear",
            "\(home)/.npm-global/bin/linear",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func runQuery(cli: String) -> Result<[LinearIssue], CLIError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["api", query]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["NO_COLOR"] = "1"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failure(CLIError(message: "Couldn't run the Linear CLI."))
        }

        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)

        // Drain stderr concurrently so a chatty CLI can't block on a full pipe.
        var errData = Data()
        let errGroup = DispatchGroup()
        errGroup.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errGroup.wait()
        timeout.cancel()

        if process.terminationReason == .uncaughtSignal {
            return .failure(CLIError(message: "Linear didn't respond in time."))
        }

        guard let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if err.localizedCaseInsensitiveContains("auth") || err.localizedCaseInsensitiveContains("credential") {
                return .failure(CLIError(message: "Run `linear auth login` in Terminal."))
            }
            return .failure(CLIError(message: err.isEmpty ? "Unexpected response from Linear." : String(err.prefix(140))))
        }

        if let errors = json["errors"] as? [[String: Any]], let first = errors.first?["message"] as? String {
            return .failure(CLIError(message: first))
        }

        guard
            let data = json["data"] as? [String: Any],
            let viewer = data["viewer"] as? [String: Any],
            let assigned = viewer["assignedIssues"] as? [String: Any],
            let nodes = assigned["nodes"] as? [[String: Any]]
        else {
            return .failure(CLIError(message: "Unexpected response from Linear."))
        }

        let issues = nodes.compactMap { node -> LinearIssue? in
            guard let identifier = node["identifier"] as? String,
                  let title = node["title"] as? String,
                  let state = node["state"] as? [String: Any] else { return nil }
            return LinearIssue(
                id: identifier,
                title: title,
                url: (node["url"] as? String).flatMap(URL.init(string:)),
                priority: node["priority"] as? Int ?? 0,
                stateName: state["name"] as? String ?? "",
                stateType: state["type"] as? String ?? "",
                stateColorHex: state["color"] as? String ?? "#888888"
            )
        }
        return .success(issues)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(cleaned, radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
