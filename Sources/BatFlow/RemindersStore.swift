import EventKit
import SwiftUI
import AppKit

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    let dueHasTime: Bool
    let creationDate: Date?
}

struct ReminderListInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
}

/// Reads and writes Apple Reminders through EventKit. Changes land in the same
/// iCloud lists your iPhone and Apple Watch use, so sync comes for free.
@MainActor
final class RemindersStore: ObservableObject {
    static let shared = RemindersStore()

    enum Access { case notDetermined, granted, denied }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var lists: [ReminderListInfo] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var isLoading = false
    @Published var selectedListID: String {
        didSet {
            UserDefaults.standard.set(selectedListID, forKey: Self.listKey)
            reload()
        }
    }

    private static let listKey = "remindersListID"
    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?
    private var isActive = false
    private var needsReload = true

    private init() {
        selectedListID = UserDefaults.standard.string(forKey: Self.listKey) ?? ""
        access = Self.currentAccess()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.needsReload = true
                if self.isActive { self.reload() }
            }
        }
    }

    var selectedList: ReminderListInfo? {
        lists.first { $0.id == selectedListID }
    }

    /// The card calls this on appear; reloads are skipped while nothing is on screen.
    func activate() {
        isActive = true
        access = Self.currentAccess()
        if access == .granted && (needsReload || lists.isEmpty) { reload() }
    }

    func deactivate() {
        isActive = false
    }

    func requestAccess() {
        Task {
            do {
                _ = try await store.requestFullAccessToReminders()
            } catch {
                NSLog("BatFlow: reminders access request failed: \(error)")
            }
            access = Self.currentAccess()
            if access == .granted { reload() }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func reload() {
        guard access == .granted else { return }
        needsReload = false

        let calendars = store.calendars(for: .reminder)
        lists = calendars
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { ReminderListInfo(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color)) }

        if store.calendar(withIdentifier: selectedListID) == nil,
           let fallback = store.defaultCalendarForNewReminders() ?? calendars.first {
            // Assigning triggers didSet → reload again with a valid list.
            selectedListID = fallback.calendarIdentifier
            return
        }
        guard let calendar = store.calendar(withIdentifier: selectedListID) else {
            reminders = []
            return
        }

        isLoading = reminders.isEmpty
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let requestedList = selectedListID
        store.fetchReminders(matching: predicate) { [weak self] result in
            // EventKit calls back on a background queue; snapshot to value types first.
            let items = (result ?? []).map { reminder -> ReminderItem in
                let components = reminder.dueDateComponents
                return ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    dueDate: components.flatMap { Calendar.current.date(from: $0) },
                    dueHasTime: components?.hour != nil,
                    creationDate: reminder.creationDate
                )
            }
            .sorted(by: Self.ordering)

            DispatchQueue.main.async {
                guard let self, self.selectedListID == requestedList else { return }
                self.isLoading = false
                if self.reminders != items {
                    self.reminders = items
                }
            }
        }
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let calendar = store.calendar(withIdentifier: selectedListID) else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
            reload()
        } catch {
            NSLog("BatFlow: failed to save reminder: \(error)")
        }
    }

    func complete(id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == id }
        } catch {
            NSLog("BatFlow: failed to complete reminder: \(error)")
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Dated reminders first (soonest first), then undated ones oldest first, like Reminders' "Due Date" sort.
    nonisolated private static func ordering(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
        }
    }
}
