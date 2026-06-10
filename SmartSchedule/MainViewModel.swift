import SwiftUI

@MainActor
class MainViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var parsedItem: ParsedItem?
    @Published var isProcessing = false
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var alertIsSuccess = false

    private let calendarManager = CalendarManager()
    private let remindersManager = RemindersManager()

    func parseInput() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        parsedItem = NLPParser.shared.parse(inputText)
    }

    func confirmAction() async {
        guard let item = parsedItem else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            switch item.type {
            case .calendarEvent:
                let start = item.startDate ?? defaultStartDate()
                let end = item.endDate ?? start.addingTimeInterval(3600)
                try await calendarManager.addEvent(
                    title: item.title,
                    startDate: start,
                    endDate: end,
                    notes: item.notes
                )
                showSuccessAlert("'\(item.title)'을(를) 캘린더에 추가했어요.")

            case .reminder:
                try await remindersManager.addReminder(
                    title: item.title,
                    dueDate: item.startDate,
                    notes: item.notes,
                    categoryName: item.reminderCategory?.rawValue
                )
                let list = item.reminderCategory?.rawValue ?? "미리알림"
                showSuccessAlert("'\(item.title)'을(를) '\(list)' 목록에 추가했어요.")
            }
            inputText = ""
            parsedItem = nil
        } catch {
            showErrorAlert(error.localizedDescription)
        }
    }

    func cancel() {
        parsedItem = nil
    }

    func editType(_ type: ScheduleType) {
        parsedItem?.type = type
        if type == .calendarEvent {
            parsedItem?.reminderCategory = nil
        } else if parsedItem?.reminderCategory == nil {
            parsedItem?.reminderCategory = .personal
        }
    }

    func editTitle(_ title: String) {
        parsedItem?.title = title
    }

    func editDate(_ date: Date?) {
        parsedItem?.startDate = date
        parsedItem?.endDate = date.map { $0.addingTimeInterval(3600) }
    }

    func editCategory(_ category: ReminderCategory) {
        parsedItem?.reminderCategory = category
    }

    private func defaultStartDate() -> Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return Calendar.current.date(from: components) ?? Date()
    }

    private func showSuccessAlert(_ message: String) {
        alertMessage = message
        alertIsSuccess = true
        showAlert = true
    }

    private func showErrorAlert(_ message: String) {
        alertMessage = message
        alertIsSuccess = false
        showAlert = true
    }
}
