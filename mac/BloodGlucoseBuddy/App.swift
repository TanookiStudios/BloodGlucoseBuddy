import SwiftUI

@main
struct BloodGlucoseBuddyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(state)
        } label: {
            if let title = state.menuBarTitle {
                Text(title).accessibilityIdentifier("menuBarTitle")
            } else {
                Image(systemName: "drop")
            }
        }

        Window("Blood Glucose Buddy", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(state.isSignedIn ? .suppressed : .presented)

        Window("About Maddie", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.isSignedIn {
            Text(state.readingLine)
            if let age = state.ageLine { Text(age) }
        } else {
            Text("Not signed in to Dexcom")
        }
        if let problem = state.dexcomProblem { Text(problem) }

        Divider()

        Picker("Units", selection: $state.unit) {
            ForEach(GlucoseUnit.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Open at Login", isOn: Binding(get: { state.openAtLogin }, set: { state.setOpenAtLogin($0) }))
        Menu("Discord") {
            Toggle("Show on Discord", isOn: $state.discordOn)
            Text(state.discordLine)
            if state.discordOn {
                Divider()
                Picker("Show", selection: $state.mode) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Status Word", selection: $state.verb) {
                    ForEach(StatusVerb.allCases) { Text("\($0.label) Blood Glucose").tag($0) }
                }
            }
        }

        Divider()

        Button("About Maddie…") {
            NSApp.activate()
            openWindow(id: "about")
        }
        .accessibilityIdentifier("openAbout")
        Button(state.isSignedIn ? "Settings…" : "Sign In…") {
            NSApp.activate()
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
        .accessibilityIdentifier("openSettings")
        Button("Quit Blood Glucose Buddy") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var region: DexcomRegion = .us
    @State private var busy = false
    @State private var error: String?
    @State private var note: String?
    @State private var showFinder = false

    var body: some View {
        Form {
            Section("Dexcom account") {
                if state.isSignedIn {
                    LabeledContent("Signed in as", value: state.username)
                        .accessibilityIdentifier("signedInAs")
                    LabeledContent("Region", value: state.region.label)
                    Button("Sign Out") { state.signOut() }
                } else {
                    TextField("Username, email, or phone", text: $username)
                        .textContentType(.username)
                        .accessibilityIdentifier("username")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("password")
                    Picker("Region", selection: $region) {
                        ForEach(DexcomRegion.allCases) { Text($0.label).tag($0) }
                    }
                    Text("Use your own Dexcom login, not a follower's. Phone numbers need a + and country code, like +15551234567.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                    if let note {
                        Text(note).foregroundStyle(.green)
                    }
                    if region.accountSiteURL != nil {
                        LabeledContent {
                            Button("Find My Account ID…") { showFinder = true }
                                .accessibilityIdentifier("findAccountID")
                        } label: {
                            Text("Email or phone not working?")
                            Text("Lots of Dexcom accounts need their account ID instead. Sign in to Dexcom here and we'll fill it in.")
                        }
                    }
                    Button(busy ? "Signing In…" : "Sign In") {
                        busy = true
                        error = nil
                        note = nil
                        Task {
                            error = await state.signIn(username: username, password: password, region: region)
                            busy = false
                            if error == nil { password = "" }
                        }
                    }
                    .disabled(busy || username.isEmpty || password.isEmpty)
                    .accessibilityIdentifier("signIn")
                    .keyboardShortcut(.defaultAction)
                }
            }

            Section {
                Toggle("Show my reading on Discord", isOn: $state.discordOn)
                    .accessibilityIdentifier("discordOn")
                if state.discordOn {
                    Text(state.discordLine).foregroundStyle(.secondary)
                    Picker("Show", selection: $state.mode) {
                        ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Status word", selection: $state.verb) {
                        ForEach(StatusVerb.allCases) { Text("\($0.label) Blood Glucose").tag($0) }
                    }
                    if state.mode == .dot {
                        Stepper("Low below \(Presence.format(state.lowThreshold, state.unit))",
                                value: $state.lowThreshold, in: 40...150, step: 5)
                        Stepper("High above \(Presence.format(state.highThreshold, state.unit))",
                                value: $state.highThreshold, in: 120...400, step: 5)
                    }
                    Group {
                        Text("Not showing up? In Discord, click the gear at the bottom left to open User Settings, choose Activity Privacy, and turn on \u{201C}Share your detected activities with others.\u{201D}")
                        Text("Everyone in every Discord server you're in can see it. To hide it from one server, right-click that server in Discord, choose Privacy Settings, and turn off Activity Status.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Discord")
            } footer: {
                if !state.discordOn {
                    Text("Optional. Puts your reading under your name on Discord, as a number or just a colored dot.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Not a medical device. Never make treatment decisions from Blood Glucose Buddy; use your Dexcom app or receiver. It reads Dexcom's unofficial Share feed, which can stop working without notice. Not affiliated with Dexcom or Discord.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showFinder) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sign in to Dexcom to find your account ID").font(.headline)
                    Spacer()
                    Button("Cancel") { showFinder = false }
                }
                .padding()
                if let url = region.accountSiteURL {
                    DexcomAccountFinder(startURL: url) { id in
                        username = id
                        error = nil
                        note = "Found your account ID. Now type your Dexcom password and click Sign In."
                        showFinder = false
                    }
                }
            }
            .frame(width: 520, height: 700)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
