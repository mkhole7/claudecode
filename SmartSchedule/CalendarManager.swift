import EventKit

enum PermissionError: LocalizedError {
    case denied(String)

    var errorDescription: String? {
        if case .denied(let app) = self {
            return "\(app) 접근 권한이 없습니다. 설정 > 개인 정보 보호에서 권한을 허용해 주세요."
        }
        return nil
    }
}

class CalendarManager {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized { return true }
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func addEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) async throws {
        guard await requestAccess() else {
            throw PermissionError.denied("캘린더")
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }
}
