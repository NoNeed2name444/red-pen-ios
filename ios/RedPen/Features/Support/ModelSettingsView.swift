import SwiftUI

/// Which model writes and which one checks, the on-device downloads, and the
/// hosted models the student has added.
///
/// A sheet with its own navigation, so it opens the same way from a generate
/// screen, a case and the accuracy check; Settings pushes it `embedded`,
/// inside its own stack, with no Done.
struct ModelSettingsView: View {
    /// Pushed inside someone else's navigation: no stack of its own, no Done.
    let embedded: Bool

    @EnvironmentObject private var llm: LocalLLMService
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HostedProvider?
    @State private var editingIsNew = false
    @State private var showPaywall = false
    @State private var cloudNote: String?

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        if embedded {
            form
        } else {
            NavigationStack {
                form
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        }
    }

    private var form: some View {
        Form {
            useSection
            deviceSection
            cloudSection
            ownKeySection
            Section {
                Text("A study aid, not medical advice. Generated text can be wrong even when checked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("AI models")
        .navigationBarTitleDisplayMode(.inline)
        // the one way to Pro on this screen, under the thumb
        .safeAreaInset(edge: .bottom, spacing: 0) { proBar }
        .sheet(item: $editing) { provider in
            ProviderEditor(provider: provider, isNew: editingIsNew)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { llm.refreshStatus() }
    }

    @ViewBuilder
    private var proBar: some View {
        if !llm.isPro {
            StudyActionBar {
                Button("See Pro") { showPaywall = true }
                    .buttonStyle(.bigPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Sections

    private var useSection: some View {
        Section {
            ForEach(LLMRole.allCases) { role in
                rolePicker(role)
            }
            Toggle("Check generated questions and stations", isOn: $llm.checkGenerated)
            if let cloudNote {
                Text(cloudNote).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Use")
        } footer: {
            Text("The writer plays the patient in Cases and can write MCQs and OSCE stations. The checker grades answers against their source \u{2014} every patient reply, generated questions and stations, and any card or page you ask it to check.")
        }
    }

    private func rolePicker(_ role: LLMRole) -> some View {
        let device: String = role.onDeviceModel.displayName
        let onDevice: String = "\(device) \u{00B7} Pro"
        let medicalCloud: String = "\(device), cloud \u{00B7} Pro"
        let brandCloud: String = "\(Brand.name) Cloud \u{00B7} Pro"
        return Picker(role.title, selection: binding(for: role)) {
            Text("Off").tag(LLMChoice.off)
            if llm.status[role.onDeviceModel] != .unsupported {
                Text(onDevice).tag(LLMChoice.device)
            }
            // Doctor-R1 and MedVAL in the cloud need a host: Hugging
            // Face now charges for Docker Spaces, so the choice
            // stays hidden until one is paid for
            if LocalLLMService.cloudMedicalHosted {
                Text(medicalCloud).tag(LLMChoice.cloudMedical)
            }
            Text(brandCloud).tag(LLMChoice.cloud)
            ForEach(llm.providers) { provider in
                Text(provider.name).tag(LLMChoice.hosted(provider.id))
            }
        }
    }

    private var deviceSection: some View {
        Section {
            ForEach(MedicalModel.allCases) { model in
                modelRow(model)
            }
        } header: {
            Text("On this device \u{00B7} Pro")
        } footer: {
            Text(ModelSettingsView.deviceFooter)
        }
    }

    private static var deviceFooter: String {
        let memory: String = String(format: "%.1f", MedicalModel.deviceMemoryGB)
        let size: String = "This device has \(memory) GB of memory."
        let rest: String = "The app picks the largest build that fits; devices without room for a model use a hosted one instead. Downloads are one-time and run fully offline afterwards."
        return size + " " + rest
    }

    private var cloudSection: some View {
        Section {
            LabeledContent("Writer", value: "Gemini 3.1 Pro")
            LabeledContent("Checker", value: "Gemini 3.1 Pro with MedVAL's rubric")
            LabeledContent("Status", value: llm.cloudBlocker ?? "Ready")
        } header: {
            Text("\(Brand.name) Cloud \u{00B7} Pro")
        } footer: {
            Text("Google's Gemini, with Google's Gemma and Cloudflare's models taking over when it is busy. Works on every device, including ones too small for the on-device models. Your text is sent to Google or Cloudflare to answer; \(Brand.name) does not keep it.")
        }
    }

    private var ownKeySection: some View {
        Section {
            ForEach(llm.providers) { provider in
                providerRow(provider)
            }
            .onDelete { offsets in
                let doomed = offsets.map { llm.providers[$0] }
                for provider in doomed { llm.remove(provider) }
            }
            // the presets live in a system menu (its rows cannot be styled),
            // so the chip that opens it is what stands out of the glass
            Menu {
                ForEach(HostedProvider.presets, id: \.name) { preset in
                    Button(preset.name) { add(preset) }
                }
            } label: {
                Label("Add a hosted model", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .liquidGlassChip(plane: .raised)
            }
        } header: {
            Text("Your own key \u{00B7} advanced")
        } footer: {
            Text("Your own API key, kept in the keychain on this device only. What you send goes to that provider under their terms.")
        }
    }

    /// Tap to edit; swipe, or press and hold, to delete.
    private func providerRow(_ provider: HostedProvider) -> some View {
        Button {
            edit(provider)
        } label: {
            LabeledContent(provider.name, value: provider.model)
        }
        .foregroundStyle(.primary)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { edit(provider) }
            Button("Delete", systemImage: "trash", role: .destructive) { llm.remove(provider) }
        }
    }

    private func edit(_ provider: HostedProvider) {
        editingIsNew = false
        editing = provider
    }

    private func add(_ preset: HostedProvider) {
        var fresh = preset
        fresh.id = UUID()
        editingIsNew = true
        editing = fresh
    }

    private func binding(for role: LLMRole) -> Binding<LLMChoice> {
        Binding(get: { llm.choice(for: role) }, set: { choice in
            // CramDown Cloud only once it can actually answer: Pro opens the
            // paywall, a missing sign-in says so, and the choice stays put
            if choice == .cloud || choice == .cloudMedical, let blocker = llm.cloudBlocker {
                cloudNote = blocker
                if !llm.isPro { showPaywall = true }
                return
            }
            // the medical models on the device are Pro too
            if choice == .device, !llm.isPro {
                cloudNote = "Doctor-R1 and MedVAL are part of Pro."
                showPaywall = true
                return
            }
            cloudNote = nil
            llm.setChoice(choice, for: role)
        })
    }

    @ViewBuilder
    private func modelRow(_ model: MedicalModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.displayName).font(.headline)
                Spacer()
                if let variant = model.variant() {
                    Text("\(variant.quant) \u{00B7} \(variant.bytes.gigabytes)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(model.purpose).font(.caption).foregroundStyle(.secondary)
            switch llm.status[model] ?? .notDownloaded {
            case .unsupported:
                Text("Too large for this device \u{2014} add a hosted model below.")
                    .font(.footnote).foregroundStyle(.orange)
            case .notDownloaded:
                Button { if llm.isPro { llm.download(model) } else { showPaywall = true } } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bigSecondary)
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading \u{2014} \(Int(fraction * 100))%").font(.footnote)
                }
                Button("Cancel download", role: .cancel) { llm.cancelDownload(model) }
            case .ready:
                HStack {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Remove", role: .destructive) { llm.delete(model) }
                }
                .font(.footnote)
            case .failed(let message):
                Text("Download failed: \(message)").font(.footnote).foregroundStyle(.red)
                Button("Try again") { llm.download(model) }
                    .buttonStyle(.bigSecondary)
            }
        }
        // the small ones (Cancel download, Remove) stay flat; the one thing
        // to do next - Download, Try again - stands out of the glass
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}

/// Adding or changing one hosted model.
private struct ProviderEditor: View {
    @EnvironmentObject private var llm: LocalLLMService
    @Environment(\.dismiss) private var dismiss
    @State var provider: HostedProvider
    let isNew: Bool
    @State private var key = ""
    @State private var testing = false
    @State private var testResult: String?

    /// Where the saved key was meant to go: the stored key is only ever sent
    /// there, never to an address typed since.
    private let savedBaseURL: String

    init(provider: HostedProvider, isNew: Bool) {
        _provider = State(initialValue: provider)
        self.isNew = isNew
        self.savedBaseURL = isNew ? "" : provider.baseURL
    }

    /// https, or plain http only to this device or the local network (a
    /// llama.cpp server on a Mac): a key never crosses the internet unencrypted.
    static func safeAddress(_ address: String) -> Bool {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return false }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        return host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
            || host.hasPrefix("192.168.") || host.hasPrefix("10.")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Every row here is something you type into or set, so each
                // is its own raised slab (the picker and toggle too, so the
                // section reads as one stack rather than half cells, half slabs).
                Section {
                    TextField("Name", text: $provider.name)
                        .popFieldRow()
                    Picker("API", selection: $provider.kind) {
                        ForEach(HostedProvider.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .popFieldRow()
                    TextField("Address", text: $provider.baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .popFieldRow()
                    TextField("Model", text: $provider.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .popFieldRow()
                }
                Section {
                    Toggle("Needs an API key", isOn: $provider.needsKey)
                        .popFieldRow()
                    if provider.needsKey {
                        SecureField(isNew ? "API key" : "API key (leave empty to keep)", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .popFieldRow()
                    }
                } footer: {
                    Text("Stored in the keychain on this device. Never synced, never sent anywhere except to this address.")
                }
                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            if testing { ProgressView().controlSize(.small) }
                            Text("Test")
                        }
                    }
                    .disabled(testing)
                    if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var title: String {
        if isNew { return "Add hosted model" }
        return provider.name
    }

    /// Everything filled in, a safe address, and a key wherever one is needed.
    private var canSave: Bool {
        if provider.name.isEmpty || provider.baseURL.isEmpty || provider.model.isEmpty { return false }
        if !Self.safeAddress(provider.baseURL) { return false }
        // a new address needs its key typed again
        let moved: Bool = provider.baseURL != savedBaseURL
        if provider.needsKey && key.isEmpty && moved { return false }
        return true
    }

    private func save() {
        let typedKey: String? = key.isEmpty ? nil : key
        llm.upsert(provider, key: typedKey)
        dismiss()
    }

    private func test() async {
        guard Self.safeAddress(provider.baseURL) else {
            testResult = "Use an https:// address (plain http only for this device or your local network)."
            return
        }
        // the stored key goes only to the address it was saved for
        if key.isEmpty && provider.baseURL != savedBaseURL && provider.needsKey {
            testResult = "The address changed - enter the API key again to test it."
            return
        }
        testing = true
        defer { testing = false }
        // tested as typed, without saving: Cancel still means nothing changed
        do {
            let reply = try await HostedLLMClient(provider: provider, bearer: key.isEmpty ? nil : key)
                .complete([.user("Reply with the single word: ready")], maxTokens: 20, temperature: 0)
            testResult = "Answered: \(reply.prefix(60))"
        } catch {
            testResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
