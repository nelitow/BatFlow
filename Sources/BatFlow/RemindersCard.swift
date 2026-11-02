import SwiftUI

struct RemindersCard: View {
    @ObservedObject private var store = RemindersStore.shared
    @State private var newTitle = ""
    @FocusState private var isFieldFocused: Bool

    private var tint: Color { store.selectedList?.color ?? .orange }

    var body: some View {
        NotchCard(title: "Reminders", systemImage: "checklist", tint: tint) {
            if store.access == .granted {
                listPicker
            }
        } content: {
            switch store.access {
            case .notDetermined:
                CardPlaceholder(
                    systemImage: "checklist",
                    title: "Your Reminders, Here",
                    message: "BatFlow uses your iCloud lists, so tasks stay in sync with iPhone and Apple Watch."
                ) {
                    Button("Allow Access") { store.requestAccess() }
                        .controlSize(.small)
                }
            case .denied:
                CardPlaceholder(
                    systemImage: "lock.fill",
                    title: "No Access to Reminders",
                    message: "Turn on BatFlow in Privacy & Security › Reminders."
                ) {
                    Button("Open System Settings") { store.openPrivacySettings() }
                        .controlSize(.small)
                }
            case .granted:
                VStack(spacing: 0) {
                    reminderList
                    newReminderField
                }
            }
        }
        .onAppear { store.activate() }
        .onDisappear { store.deactivate() }
    }

    private var listPicker: some View {
        Menu {
            Picker("List", selection: $store.selectedListID) {
                ForEach(store.lists) { list in
                    Text(list.title).tag(list.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 3) {
                Text(store.selectedList?.title ?? "List")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var reminderList: some View {
        if store.reminders.isEmpty && !store.isLoading {
            CardPlaceholder(systemImage: "checkmark.circle", title: "All Done", message: "No reminders in this list.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.reminders) { item in
                        ReminderRow(item: item, tint: tint) { store.complete(id: item.id) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var newReminderField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(tint)
            TextField("New Reminder", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFieldFocused)
                .onSubmit {
                    store.add(title: newTitle)
                    newTitle = ""
                    isFieldFocused = true
                }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let tint: Color
    let onComplete: () -> Void

    /// Reminders.app fills the circle, then waits a beat so an accidental click can be undone.
    @State private var isChecked = false
    @State private var pending: DispatchWorkItem?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .strokeBorder(isChecked ? tint : Color.white.opacity(0.35), lineWidth: 1.2)
                    if isChecked {
                        Circle().fill(tint).padding(3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 15, height: 15)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isChecked ? .secondary : .primary)
                    .lineLimit(2)
                if let due = item.dueDate {
                    Text(Self.dueText(due, hasTime: item.dueHasTime))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Self.isOverdue(due, hasTime: item.dueHasTime) ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 24)
        }
    }

    private func toggle() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isChecked.toggle() }
        pending?.cancel()
        guard isChecked else { return }
        let work = DispatchWorkItem { onComplete() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private static func isOverdue(_ date: Date, hasTime: Bool) -> Bool {
        hasTime ? date < .now : Calendar.current.startOfDay(for: .now) > date
    }

    private static func dueText(_ date: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) {
            day = "Today"
        } else if cal.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else if cal.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day())
        }
        guard hasTime else { return day }
        return "\(day), \(date.formatted(date: .omitted, time: .shortened))"
    }
}
