import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Daily Challenge Notification Scheduling

enum DailyChallengeNotifications {
    static let identifier = "com.gamehub.dailyChallenge"

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func currentAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    /// Schedules (or reschedules) a repeating daily local notification at the given time.
    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Daily Challenge"
        content.body = "Your daily challenge is ready — jump in and beat your best score!"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

// MARK: - Settings Screen

struct SettingsView: View {
    @EnvironmentObject var store: GameSessionStore

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("dailyChallengeHour") private var dailyChallengeHour = 9
    @AppStorage("dailyChallengeMinute") private var dailyChallengeMinute = 0

    @State private var showResetConfirmation = false
    @State private var showPermissionDeniedAlert = false
    @State private var showResetConfirmationToast = false

    // Bridges the stored hour/minute Ints to a Date for the DatePicker,
    // and reschedules the notification whenever the picker changes.
    private var dailyChallengeTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = dailyChallengeHour
                components.minute = dailyChallengeMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                dailyChallengeHour = components.hour ?? 9
                dailyChallengeMinute = components.minute ?? 0
                if notificationsEnabled {
                    DailyChallengeNotifications.schedule(hour: dailyChallengeHour, minute: dailyChallengeMinute)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection
                dataSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Reset all stats?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Everything", role: .destructive) {
                    store.resetAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every recorded score and map pin. This can't be undone.")
            }
            .alert("Notifications Off", isPresented: $showPermissionDeniedAlert) {
                #if canImport(UIKit)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                #endif
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable notifications for this app in iOS Settings to get your daily challenge reminder.")
            }
            .onAppear {
                syncAuthorizationStatus()
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Daily Challenge Reminders", isOn: Binding(
                get: { notificationsEnabled },
                set: { handleToggle($0) }
            ))

            if notificationsEnabled {
                DatePicker(
                    "Reminder Time",
                    selection: dailyChallengeTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Get a daily local reminder to jump in and beat your best score.")
        }
    }

    private var dataSection: some View {
        Section {
            HStack {
                Label("Total Games Played", systemImage: "gamecontroller.fill")
                Spacer()
                Text("\(store.sessions.count)")
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset All Stats", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Deletes every recorded game session — scores, dates, and map pins.")
        }
    }

    private func handleToggle(_ isOn: Bool) {
        if isOn {
            DailyChallengeNotifications.requestAuthorization { granted in
                if granted {
                    notificationsEnabled = true
                    DailyChallengeNotifications.schedule(hour: dailyChallengeHour, minute: dailyChallengeMinute)
                } else {
                    notificationsEnabled = false
                    showPermissionDeniedAlert = true
                }
            }
        } else {
            notificationsEnabled = false
            DailyChallengeNotifications.cancel()
        }
    }

    // If the person revoked notification permission in iOS Settings since
    // last time, reflect that here instead of showing a toggle that's on
    // but silently doesn't fire.
    private func syncAuthorizationStatus() {
        DailyChallengeNotifications.currentAuthorizationStatus { status in
            if status == .denied {
                notificationsEnabled = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(GameSessionStore.shared)
}
