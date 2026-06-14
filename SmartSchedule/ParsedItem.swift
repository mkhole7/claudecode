import Foundation

enum ScheduleType: String, CaseIterable {
    case calendarEvent = "캘린더 일정"
    case reminder = "미리알림"
}

enum ReminderCategory: String, CaseIterable {
    case personal = "개인"
    case work = "직장"
    case shopping = "쇼핑"
    case health = "건강"
    case other = "기타"

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .work: return "briefcase.fill"
        case .shopping: return "cart.fill"
        case .health: return "heart.fill"
        case .other: return "star.fill"
        }
    }
}

struct ParsedItem {
    var type: ScheduleType
    var title: String
    var startDate: Date?
    var endDate: Date?
    var notes: String?
    var reminderCategory: ReminderCategory?
    var originalText: String
    var confidence: Double

    var formattedDate: String {
        guard let date = startDate else { return "날짜 없음" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E) a h:mm"
        return formatter.string(from: date)
    }
}
