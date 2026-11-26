import EventKit
import SwiftUI

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var requestingAccess = false
    @Published var error: String?
    @Published var selectedID: String {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: selectionKey)
            refresh()
        }
    }
    private let store = EKEventStore()
    private let selectionKey: String

    init(selectionKey: String) {
        self.selectionKey = selectionKey
        selectedID = UserDefaults.standard.string(forKey: selectionKey) ?? ""
    }

    var selectedCalendar: EKCalendar? { calendars.first { $0.calendarIdentifier == selectedID } }
    var canEdit: Bool { selectedCalendar?.allowsContentModifications == true }

    func requestAccess() async {
        requestingAccess = true
        defer { requestingAccess = false }
        do {
            _ = try await store.requestFullAccessToEvents()
            refresh()
        } catch { self.error = error.localizedDescription }
    }

    func refresh() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .fullAccess else {
            calendars = []
            events = []
            return
        }
        calendars = store.calendars(for: .event).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        guard let selectedCalendar else { events = []; return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [selectedCalendar])
        events = store.events(matching: predicate).sorted {
            if $0.startDate == $1.startDate { return ($0.title ?? "") < ($1.title ?? "") }
            return $0.startDate < $1.startDate
        }
    }

    func addEvent(title: String, start: Date, end: Date, allDay: Bool) throws {
        guard authorization == .fullAccess, let selectedCalendar, canEdit else {
            throw CalendarFailure.readOnly
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, end > start else { throw CalendarFailure.invalidEvent }
        let event = EKEvent(eventStore: store)
        event.calendar = selectedCalendar
        event.title = cleanTitle
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        try store.save(event, span: .thisEvent)
        refresh()
    }
}

private enum CalendarFailure: LocalizedError {
    case readOnly, invalidEvent
    var errorDescription: String? {
        switch self {
        case .readOnly: return "Choose a calendar you can edit before adding an event."
        case .invalidEvent: return "Enter a title and an end time after the start time."
        }
    }
}
