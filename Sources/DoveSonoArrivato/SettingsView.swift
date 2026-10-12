import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("keepOnTop") private var keepOnTop = true
    @AppStorage("showAtLaunch") private var showAtLaunch = true
    @AppStorage("defaultPaperColor") private var defaultPaperColor = PaperColor.yellow.rawValue
    @AppStorage("panelShortcutAvailable") private var panelShortcutAvailable = false
    @AppStorage("staleAfterDays") private var staleAfterDays = 7
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(L("Lingua", "Language")) {
                Picker(L("Lingua dell’app", "App language"), selection: $language) {
                    Text(L("Come il sistema", "Same as system")).tag(AppLanguage.system.rawValue)
                    Text("Italiano").tag(AppLanguage.italian.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }
                Text(L("Vale subito per il pannello, il widget e i promemoria.", "Applies right away to the panel, the widget and reminders."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("Pannello", "Panel")) {
                Text(panelShortcutAvailable
                     ? L("Apri o nascondi i post-it da qualsiasi app con ⌃⌥Spazio.", "Show or hide your notes from any app with ⌃⌥Space.")
                     : L("La scorciatoia ⌃⌥Spazio non è disponibile. Apri i post-it dalla barra dei menu.",
                         "The ⌃⌥Space shortcut is taken. Open your notes from the menu bar."))
                    .font(.callout).foregroundStyle(.secondary)
                Toggle(L("Mantieni il pannello sopra le altre finestre", "Keep the panel above other windows"), isOn: $keepOnTop)
                Toggle(L("Mostra il pannello quando apri l’app", "Show the panel when the app opens"), isOn: $showAtLaunch)
                Toggle(L("Apri all’accesso al Mac", "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        loginNeedsApproval = LoginItem.needsApproval
                        if LoginItem.isEnabled != enabled && !loginNeedsApproval { launchAtLogin = LoginItem.isEnabled }
                    }
                if loginNeedsApproval {
                    HStack {
                        Text(L("macOS chiede la tua conferma in Elementi login.", "macOS needs your approval in Login Items."))
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Apri Elementi login", "Open Login Items")) { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }
            Section(L("Nuovi post-it", "New notes")) {
                Picker(L("Colore iniziale", "Starting color"), selection: $defaultPaperColor) {
                    ForEach(PaperColor.allCases) { color in
                        Text(color.label).tag(color.rawValue)
                    }
                }
            }
            Section(L("Lavori fermi", "Stale notes")) {
                Picker(L("Segnala i lavori non toccati da", "Flag notes untouched for"), selection: $staleAfterDays) {
                    Text(L("Mai", "Never")).tag(0)
                    ForEach([3, 7, 14, 30], id: \.self) { days in Text(L("\(days) giorni", "\(days) days")).tag(days) }
                }
                Text(L("Un orologio con i giorni compare sul titolo. I lavori in attesa con un promemoria futuro non vengono segnalati.",
                       "A clock with the number of days appears on the title. Notes waiting with an upcoming reminder are not flagged."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L("Le tue note", "Your notes")) {
                Text(L("Ogni modifica si salva automaticamente su questo Mac. Puoi chiudere il post-it senza premere Salva.",
                       "Every change is saved automatically on this Mac. Close a note any time, there is no Save button."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L("Mostra la cartella delle note", "Show notes folder")) {
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("DoveSonoArrivato")
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = L("Non riesco ad aprire la cartella", "The folder can’t be opened")
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                }
            }
            Text(L("Le impostazioni si salvano automaticamente.", "Settings are saved automatically."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 700)
    }
}
