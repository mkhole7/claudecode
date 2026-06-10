import EventKit

class RemindersManager {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .authorized { return true }
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func addReminder(title: String, dueDate: Date?, notes: String? = nil, categoryName: String? = nil) async throws {
        guard await requestAccess() else {
            throw PermissionError.denied("미리알림")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        // Try to find a matching list by category name, fall back to default
        if let categoryName {
            reminder.calendar = store.calendars(for: .reminder)
                .first { $0.title == categoryName }
                ?? store.defaultCalendarForNewReminders
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders
        }

        try store.save(reminder, commit: true)
    }
}
