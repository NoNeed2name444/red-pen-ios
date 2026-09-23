import SwiftUI

/// Which model writes and which one checks, the on-device downloads, and the
/// hosted models the student has added.
///
/// A sheet with its own navigation, so it opens the same way from Settings,
/// from a generate screen and from a case.
struct ModelSettingsView: View {
    @EnvironmentObject private var llm: LocalLLMService
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HostedProvider?
    @State private var editingIsNew = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LLMRole.allCases) { role in
                        Picker(role.title, selection: binding(for: role)) {
                            Text("Off").tag(LLMChoice.off)
                            if llm.status[role.onDeviceModel] != .unsupported {
                                Text("\(role.onDeviceModel.displayName) (this device)").tag(LLMChoice.device)
                            }
                            ForEach(llm.providers) { provider in
                                Text(provider.name).tag(LLMChoice.hosted(provider.id))
                            }
                        }
                    }
                    Toggle("Check generated questions and stations", isOn: $llm.checkGenerated)
                } header: {
                    Text("Use")
                } footer: {
                    Text("The writer plays the patient in Cases and can write MCQs and OSCE stations. The checker grades answers against their source \u{2014} every patient reply, generated questions and stations, and any card or page you ask it to check.")
                }

                Section {
                    ForEach(MedicalModel.allCases) { model in
                        modelRow(model)
                    }
                } header: {
                    Text("On this device")
                } footer: {
                    Text("This device has \(String(format: "%.1f", MedicalModel.deviceMemoryGB)) GB of memory. The app picks the largest build that fits; devices without room for a model use a hosted one instead. Downloads are one-time and run fully offline afterwards.")
                }

                Section {
                    ForEach(llm.providers) { provider in
                        Button {
                            editingIsNew = false
                            editing = provider
                        } label: {
                            LabeledContent(provider.name, value: provider.model)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { llm.providers[$0] }
                        for provider in doomed { llm.remove(provider) }
                    }
                    Menu {
                        ForEach(HostedProvider.presets, id: \.name) { preset in
                            Button(preset.name) {
                                var fresh = preset
                                fresh.id = UUID()
                                editingIsNew = true
                                editing = fresh
                            }
                        }
                    } label: {
                        Label("Add a hosted model", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Hosted models")
                } footer: {
                    Text("Your own API key, kept in the keychain on this device only. What you send goes to that provider under their terms. Baichuan-M2-32B is too large for any phone, so it runs hosted.")
                }

                Section {
                    Text("A study aid, not medical advice. Generated text can be wrong even when checked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { provider in
                ProviderEditor(provider: provider, isNew: editingIsNew)
            }
            .onAppear { llm.refreshStatus() }
        }
    }

    private func binding(for role: LLMRole) -> Binding<LLMChoice> {
        Binding(get: { llm.choice(for: role) }, set: { llm.setChoice($0, for: role) })
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
                Button { llm.download(model) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
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
            }
        }
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

    init(provider: HostedProvider, isNew: Bool) {
        _provider = State(initialValue: provider)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $provider.name)
                    Picker("API", selection: $provider.kind) {
                        ForEach(HostedProvider.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Address", text: $provider.baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model", text: $provider.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Toggle("Needs an API key", isOn: $provider.needsKey)
                    if provider.needsKey {
                        SecureField(isNew ? "API key" : "API key (leave empty to keep)", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
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
            .navigationTitle(isNew ? "Add hosted model" : provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        llm.upsert(provider, key: key.isEmpty ? nil : key)
                        dismiss()
                    }
                    .disabled(provider.name.isEmpty || provider.baseURL.isEmpty || provider.model.isEmpty)
                }
            }
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        // saved first so the key is in the keychain where the client reads it
        llm.upsert(provider, key: key.isEmpty ? nil : key)
        do {
            let reply = try await HostedLLMClient(provider: provider)
                .complete([.user("Reply with the single word: ready")], maxTokens: 20, temperature: 0)
            testResult = "Answered: \(reply.prefix(60))"
        } catch {
            testResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
