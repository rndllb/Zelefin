import SwiftUI

struct SiloProfilePickerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [SiloHouseholdProfile] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsCreate = false
    @State private var newName = ""
    @State private var newPIN = ""
    @State private var newIsChild = false

    var body: some View {
        ZStack {
            if isLoading && profiles.isEmpty {
                LoginPalette.canvas.ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            } else {
                SiloWhoIsWatchingView(
                    profiles: profiles,
                    currentID: session.session?.profileID,
                    footerTitle: session.canChangeSiloPassword ? "Add Profile" : nil,
                    isBusy: isSaving,
                    errorMessage: errorMessage,
                    onSelect: { profile, pin in
                        await confirm(profile, pin: pin)
                    },
                    onFooter: session.canChangeSiloPassword ? { showsCreate = true } : nil
                )
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .sheet(isPresented: $showsCreate) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $newName)
                        Toggle("Kids profile", isOn: $newIsChild)
                        SecureField("PIN (optional)", text: $newPIN)
                            .keyboardType(.numberPad)
                    } footer: {
                        Text("A PIN locks this person on this login. Leave it empty for an unlocked profile.")
                    }
                    Section {
                        Button("Create Profile") {
                            Task { await create() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .zelefinSettingsChrome(title: "Add Profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showsCreate = false }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await session.siloAPI?.profiles() ?? session.householdProfiles
            profiles = loaded
            errorMessage = nil
        } catch {
            if profiles.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confirm(_ profile: SiloHouseholdProfile, pin: String?) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await session.applySiloProfile(profile, pin: pin)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let pinValue = newPIN.trimmingCharacters(in: .whitespacesAndNewlines)
            try await session.createSiloProfile(
                name: newName,
                pin: pinValue.isEmpty ? nil : pinValue,
                isChild: newIsChild
            )
            showsCreate = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
