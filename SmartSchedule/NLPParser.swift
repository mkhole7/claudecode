import Foundation

class NLPParser {
    static let shared = NLPParser()

    private let calendarKeywords = [
        "회의", "미팅", "meeting", "약속", "세미나", "강의", "수업", "면접",
        "파티", "행사", "이벤트", "콘서트", "공연", "발표", "프레젠테이션",
        "만남", "식사", "출장", "여행", "결혼식", "돌잔치", "모임", "방문"
    ]

    private let reminderKeywords = [
        "잊지마", "잊지 마", "기억", "할일", "해야", "반드시", "꼭", "잊으면",
        "잊지말고", "메모"
    ]

    private let workKeywords = [
        "보고서", "제출", "이메일", "업무", "회사", "프로젝트", "기획서",
        "계획서", "마감", "deadline", "작업", "처리", "서류", "결재"
    ]

    private let shoppingKeywords = [
        "사야", "사기", "구매", "마트", "쇼핑", "장보기", "구입", "주문",
        "배달", "택배", "물건", "살", "구하", "사다"
    ]

    private let healthKeywords = [
        "병원", "치과", "한의원", "진료", "약국", "운동", "헬스", "조깅",
        "건강검진", "검진", "복약", "약 먹", "약먹"
    ]

    private let dayNames: [(String, Int)] = [
        ("월요일", 2), ("화요일", 3), ("수요일", 4),
        ("목요일", 5), ("금요일", 6), ("토요일", 7), ("일요일", 1)
    ]

    func parse(_ text: String) -> ParsedItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let date = extractDate(from: trimmed)
        let hasTime = hasTimeExpression(in: trimmed)
        let type = determineType(from: trimmed, hasDate: date != nil, hasTime: hasTime)
        let title = extractTitle(from: trimmed)
        let category = type == .reminder ? determineCategory(from: trimmed) : nil

        return ParsedItem(
            type: type,
            title: title.isEmpty ? trimmed : title,
            startDate: date,
            endDate: date.map { $0.addingTimeInterval(3600) },
            reminderCategory: category,
            originalText: trimmed,
            confidence: calculateConfidence(text: trimmed, type: type, date: date)
        )
    }

    // MARK: - Date Extraction

    func extractDate(from text: String) -> Date? {
        let calendar = Calendar.current
        var baseDate = Date()
        var hasDate = false
        var hasTime = false
        var hour = 9
        var minute = 0
        var isPM = false

        // Relative day
        if text.contains("오늘") {
            hasDate = true
        } else if text.contains("내일") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: baseDate)!
            hasDate = true
        } else if text.contains("모레") {
            baseDate = calendar.date(byAdding: .day, value: 2, to: baseDate)!
            hasDate = true
        } else if text.contains("글피") {
            baseDate = calendar.date(byAdding: .day, value: 3, to: baseDate)!
            hasDate = true
        }

        // Specific "N월 M일"
        if let (month, day) = extractMonthDay(from: text) {
            var components = calendar.dateComponents([.year], from: Date())
            components.month = month
            components.day = day
            if let specificDate = calendar.date(from: components) {
                baseDate = specificDate
                hasDate = true
            }
        }

        // Day of week
        let isNextWeek = text.contains("다음주") || text.contains("다음 주")
        for (dayName, weekday) in dayNames {
            if text.contains(dayName) {
                let today = calendar.component(.weekday, from: Date())
                var daysAhead = weekday - today
                if daysAhead <= 0 || isNextWeek { daysAhead += 7 }
                baseDate = calendar.date(byAdding: .day, value: daysAhead, to: Date())!
                hasDate = true
                break
            }
        }

        // AM/PM context
        if text.contains("오후") || text.contains("저녁") || text.contains("밤") {
            isPM = true
        }

        // Meal time defaults
        if text.contains("저녁") && !hasTimeExpression(in: text) {
            hour = 18; hasTime = true
        } else if text.contains("아침") && !hasTimeExpression(in: text) {
            hour = 8; hasTime = true
        } else if text.contains("점심") && !hasTimeExpression(in: text) {
            hour = 12; hasTime = true
        }

        // "N시 M분" or "N시"
        if let (h, m) = extractHourMinute(from: text) {
            hour = h
            minute = m
            hasTime = true
            if isPM && hour < 12 { hour += 12 }
            if !isPM && !text.contains("오전") && hour < 9 { hour += 12 }
        }

        guard hasDate || hasTime else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hasTime ? hour : 9
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func extractMonthDay(from text: String) -> (Int, Int)? {
        let pattern = try? NSRegularExpression(pattern: "(\\d{1,2})월\\s*(\\d{1,2})일")
        guard let match = pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let monthRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange]) else { return nil }
        return (month, day)
    }

    private func extractHourMinute(from text: String) -> (Int, Int)? {
        let pattern = try? NSRegularExpression(pattern: "(\\d{1,2})시(?:\\s*(\\d{1,2})분)?")
        guard let match = pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let hour = Int(text[hourRange]) else { return nil }
        var minute = 0
        if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
           let minRange = Range(match.range(at: 2), in: text),
           let m = Int(text[minRange]) {
            minute = m
        }
        return (hour, minute)
    }

    func hasTimeExpression(in text: String) -> Bool {
        let pattern = try? NSRegularExpression(pattern: "\\d{1,2}시")
        return pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Type Detection

    private func determineType(from text: String, hasDate: Bool, hasTime: Bool) -> ScheduleType {
        for keyword in calendarKeywords where text.contains(keyword) { return .calendarEvent }
        for keyword in reminderKeywords + shoppingKeywords where text.contains(keyword) { return .reminder }
        if hasTime { return .calendarEvent }
        return .reminder
    }

    // MARK: - Title Extraction

    func extractTitle(from text: String) -> String {
        var result = text
        let patterns = [
            "다음\\s*주\\s*[가-힣]*요일",
            "이번\\s*주\\s*[가-힣]*요일",
            "[가-힣]*요일",
            "\\d{1,2}월\\s*\\d{1,2}일",
            "오늘|내일|모레|글피",
            "오전\\s*\\d{1,2}시(?:\\s*\\d{1,2}분)?",
            "오후\\s*\\d{1,2}시(?:\\s*\\d{1,2}분)?",
            "\\d{1,2}시\\s*\\d{1,2}분",
            "\\d{1,2}시",
            "오전|오후|저녁|아침|점심|밤",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        let cleaned = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }

    // MARK: - Category Detection

    private func determineCategory(from text: String) -> ReminderCategory {
        for keyword in workKeywords where text.contains(keyword) { return .work }
        for keyword in shoppingKeywords where text.contains(keyword) { return .shopping }
        for keyword in healthKeywords where text.contains(keyword) { return .health }
        return .personal
    }

    // MARK: - Confidence

    private func calculateConfidence(text: String, type: ScheduleType, date: Date?) -> Double {
        var score = 0.4
        if date != nil { score += 0.3 }
        let keywords = type == .calendarEvent ? calendarKeywords : reminderKeywords + shoppingKeywords + workKeywords
        for keyword in keywords where text.contains(keyword) { score += 0.2; break }
        if hasTimeExpression(in: text) { score += 0.1 }
        return min(score, 1.0)
    }
}
