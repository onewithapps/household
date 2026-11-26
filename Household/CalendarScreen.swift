import EventKit
import SwiftUI

struct CalendarScreen: View {
    @StateObject private var calendar: CalendarStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPicker = false
    @State private var addingEvent = false

    init(selectionKey: String) {
        _calendar = StateObject(wrappedValue: CalendarStore(selectionKey: selectionKey))
    }

    var body: some View {
        Group {
            if calendar.authorization != .fullAccess {
                VStack(spacing: 20) {
                    ContentUnavailableView("Your shared calendar", systemImage: "calendar", description: Text(permissionDescription))
                    if calendar.authorization == .notDetermined {
                        Button("Connect Apple Calendar") { Task { await calendar.requestAccess() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(calendar.requestingAccess)
                    }
                    Button("Check permission again") { calendar.refresh() }
                    if let error = calendar.error { Text(error).foregroundStyle(.red) }
                }.padding()
            } else if calendar.selectedCalendar == nil {
                VStack(spacing: 20) {
                    ContentUnavailableView("Choose your household calendar", systemImage: "calendar.badge.checkmark", description: Text("Select the iCloud calendar you already share. It must be available in Apple Calendar on this device."))
                    if !calendar.selectedID.isEmpty {
                        Text("The previously selected calendar is no longer available.").foregroundStyle(.secondary)
                    }
                    Button("Choose calendar") { showingPicker = true }.buttonStyle(.borderedProminent)
                }.padding()
            } else {
                List {
                    Section {
                        Text(calendar.selectedCalendar?.title ?? "Calendar").font(.headline)
                        Text("Next 30 days · synced through Apple Calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if calendar.events.isEmpty {
                        ContentUnavailableView("No upcoming events", systemImage: "calendar", description: Text("Events in your selected calendar will appear here."))
                    }
                    ForEach(days, id: \.self) { day in
                        Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(events(on: day), id: \.self) { event in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(event.title ?? "Untitled event").font(.headline)
                                    Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened) + " – " + event.endDate.formatted(date: Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) ? .omitted : .abbreviated, time: .shortened))
                                        .foregroundStyle(.secondary)
                                    if let location = event.location, !location.isEmpty {
                                        Label(location, systemImage: "mappin.and.ellipse").font(.caption)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
                .refreshable { calendar.refresh() }
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItemGroup {
                if calendar.authorization == .fullAccess {
                    Button { showingPicker = true } label: { Label("Choose calendar", systemImage: "calendar.badge.gearshape") }
                    Button { calendar.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    if calendar.canEdit {
                        Button { addingEvent = true } label: { Label("Add event", systemImage: "plus") }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                List {
                    Section {
                        Text("Select the same shared iCloud calendar on each device. This choice is saved only on this device; private calendar events are never uploaded to Household.")
                    }
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                        Button {
                            calendar.selectedID = item.calendarIdentifier
                            showingPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                    Text(item.source.title + (item.allowsContentModifications ? "" : " · Read only"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.calendarIdentifier == calendar.selectedID { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if calendar.calendars.isEmpty {
                        Text("No calendars found. Add your iCloud account and accept the shared calendar in Apple Calendar first.")
                    }
                }
                .navigationTitle("Choose calendar")
                .toolbar { Button("Done") { showingPicker = false } }
            }
            .frame(minWidth: 300, minHeight: 400)
        }
        .sheet(isPresented: $addingEvent) { AddEventView(calendar: calendar) }
        .onAppear { calendar.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { calendar.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in calendar.refresh() }
    }

    private var permissionDescription: String {
        if calendar.authorization == .notDetermined {
            return "Allow calendar access, then choose your shared iCloud calendar. Your events stay in iCloud."
        }
        return "Calendar access is unavailable. In Settings → Privacy & Security → Calendars, allow Household full access, then return here."
    }

    private var days: [Date] {
        Array(Set(calendar.events.map { displayDay($0) })).sorted()
    }
    private func displayDay(_ event: EKEvent) -> Date {
        max(Calendar.current.startOfDay(for: event.startDate), Calendar.current.startOfDay(for: Date()))
    }
    private func events(on day: Date) -> [EKEvent] {
        calendar.events.filter { displayDay($0) == day }
    }
}

private struct AddEventView: View {
    @ObservedObject var calendar: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var allDay = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("New shared event") {
                    TextField("Title", text: $title)
                    Toggle("All day", isOn: $allDay)
                    DatePicker("Starts", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    if !allDay { DatePicker("Ends", selection: $end, displayedComponents: [.date, .hourAndMinute]) }
                    Text("Calendar: \(calendar.selectedCalendar?.title ?? "Unavailable")")
                    if allDay { Text("An all-day event lasts one day.").font(.caption) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Add event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let eventStart = allDay ? Calendar.current.startOfDay(for: start) : start
                            let eventEnd = allDay ? Calendar.current.date(byAdding: .day, value: 1, to: eventStart)! : end
                            try calendar.addEvent(title: title, start: eventStart, end: eventEnd, allDay: allDay)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!allDay && end <= start))
                }
            }
        }.frame(minWidth: 300, minHeight: 400)
    }
}
