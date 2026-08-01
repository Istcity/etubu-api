import AppIntents

/// Kısayollar: “Araç Bluetooth bağlanınca → Etubu’yu aç” otomasyonu için.
@available(iOS 16.0, *)
struct EtubuOpenClusterIntent: AppIntent {
    static var title: LocalizedStringResource = "Etubu’yu aç"
    static var description = IntentDescription("Etubu ekranını açar.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            EtubuClusterPresenter.shared.installOverCapacitor()
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct EtubuAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EtubuOpenClusterIntent(),
            phrases: [
                "Open \(.applicationName)",
                "\(.applicationName) aç",
                "Start \(.applicationName)",
            ],
            shortTitle: "Etubu",
            systemImageName: "car.side.fill"
        )
    }
}
