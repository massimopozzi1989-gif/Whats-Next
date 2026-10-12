import Foundation
import UserNotifications

enum ReminderPreset: String, CaseIterable, Identifiable {
    case inOneHour, tomorrow, inThreeDays, nextMonday, inOneWeek
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inOneHour: return L("Tra un’ora", "In an hour")
        case .tomorrow: return L("Domani alle 9", "Tomorrow at 9")
        case .inThreeDays: return L("Tra 3 giorni, alle 9", "In 3 days, at 9")
        case .nextMonday: return L("Lunedì alle 9", "Monday at 9")
        case .inOneWeek: return L("Tra una settimana, alle 9", "In a week, at 9")
        }
    }

    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        func atNine(daysAhead: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        switch self {
        case .inOneHour: return now.addingTimeInterval(3600)
        case .tomorrow: return atNine(daysAhead: 1)
        case .inThreeDays: return atNine(daysAhead: 3)
        case .inOneWeek: return atNine(daysAhead: 7)
        case .nextMonday:
            return calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                                     matchingPolicy: .nextTime) ?? atNine(daysAhead: 7)
        }
    }
}

struct ReminderRequest: Equatable {
    static let prefix = "reminder-"
    let identifier: String
    let date: Date
    let title: String
    let body: String
    let link: String

    // Only open "In attesa" notes with a future date ring; everything else is cancelled.
    static func requests(for notes: [WorkNote], now: Date = Date()) -> [ReminderRequest] {
        notes.compactMap { note in
            guard note.completedAt == nil, note.action == .waiting,
                  let date = note.reminderAt, date > now else { return nil }
            let waiting = note.trimmedNextStep
            return ReminderRequest(identifier: prefix + note.id.uuidString, date: date,
                                   title: note.title.isEmpty ? "What’s Next?" : note.title,
                                   body: waiting.isEmpty ? L("Sei ancora in attesa: ricontrolla.", "Still waiting: time to check.")
                                                         : L("In attesa: \(waiting)", "Waiting for: \(waiting)"),
                                   link: WidgetSnapshot.link(note).absoluteString)
        }
    }
}

// Mirrors the notes' reminders into macOS notifications and opens the post-it on a click.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let deniedKey = "notificationsDenied"
    var open: (URL) -> Void = { _ in }
    private let center = UNUserNotificationCenter.current()
    private var task: Task<Void, Never>?

    func activate() {
        center.delegate = self
    }

    // Called on every published change; coalesced so a burst of saves costs one pass.
    func reconcile(_ notes: [WorkNote]) {
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await self?.sync(ReminderRequest.requests(for: notes))
        }
    }

    private func sync(_ wanted: [ReminderRequest]) async {
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(ReminderRequest.prefix) }
        let current = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        let wantedIDs = Set(wanted.map(\.identifier))
        let changed = wanted.filter { request in
            guard let existing = current[request.identifier] else { return true }
            return existing.content.title != request.title || existing.content.body != request.body
                || existing.content.userInfo["at"] as? Double != request.date.timeIntervalSince1970
        }
        let obsolete = current.keys.filter { !wantedIDs.contains($0) }
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }
        guard !changed.isEmpty, await authorized() else { return }
        for request in changed {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = ["url": request.link, "at": request.date.timeIntervalSince1970]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
        }
    }

    private func authorized() async -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        let allowed = status == .authorized || status == .provisional
        UserDefaults.standard.set(!allowed, forKey: Self.deniedKey)
        return allowed
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = response.notification.request.content.userInfo["url"] as? String
        Task { @MainActor [weak self] in
            if let link, let url = URL(string: link) { self?.open(url) }
        }
        completionHandler()
    }
}
