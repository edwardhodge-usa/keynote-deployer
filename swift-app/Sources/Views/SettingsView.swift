import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.default
    @State private var isLoading = true
    @State private var showSavedBadge = false
    @State private var tokenStatus: TokenStatus = .unknown
    @State private var tokenValidationTask: Task<Void, Never>?

    enum TokenStatus {
        case unknown, validating, valid, invalid, missing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                vercelSection
                deploymentSection
                embedSection
            }
            .padding(32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if showSavedBadge {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
        }
        .task { loadSettings() }
    }

    // MARK: - Vercel Section

    private var vercelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VERCEL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Auth Token")
                            .font(.body.weight(.medium))
                        Spacer()
                        switch tokenStatus {
                        case .valid:
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .invalid:
                            Text("Invalid Token")
                                .font(.caption)
                                .foregroundStyle(.red)
                        case .validating:
                            ProgressView()
                                .controlSize(.small)
                        case .missing:
                            Text("Not Set")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        case .unknown:
                            EmptyView()
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField("Enter Vercel auth token...", text: $settings.vercelToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .onChange(of: settings.vercelToken) { saveAndValidate() }

                        Button("Auto-Detect") {
                            detectToken()
                        }
                        .controlSize(.small)
                    }

                    Text("Auto-detect reads from Vercel CLI config, or paste your token manually.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Divider()

                    LabeledContent("Team ID") {
                        TextField("team_...", text: $settings.vercelTeamId)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(maxWidth: 300)
                            .onChange(of: settings.vercelTeamId) { saveAndValidate() }
                    }
                }
            }
        }
    }

    // MARK: - Deployment Section

    private var deploymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEPLOYMENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Project Name Prefix") {
                        TextField("e.g. ils-", text: $settings.projectNamePrefix)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(maxWidth: 200)
                            .onChange(of: settings.projectNamePrefix) { save() }
                    }

                    Divider()

                    Toggle("Auto-copy URL", isOn: $settings.autoCopyUrl)
                        .onChange(of: settings.autoCopyUrl) { save() }

                    Toggle("Runtime Verification", isOn: $settings.enableRuntimeVerification)
                        .onChange(of: settings.enableRuntimeVerification) { save() }
                }
            }
        }
    }

    // MARK: - Embed Section

    private var embedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SECURE EMBED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Secure Embed by default", isOn: $settings.secureEmbed)
                        .onChange(of: settings.secureEmbed) { save() }

                    Text("Disables downloads and restricts iframe embedding to allowed domains.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Divider()

                    LabeledContent("Allowed Domains") {
                        TextField("*.example.com *.framer.app", text: $settings.embedAllowedDomains)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(maxWidth: 300)
                            .onChange(of: settings.embedAllowedDomains) { save() }
                    }

                    Text("Space-separated domains for CSP frame-ancestors header.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        do {
            settings = try FileOperations.loadSettings()
        } catch {
            settings = .default
        }
        isLoading = false
        Task { await validateToken() }
    }

    private func save() {
        do {
            try FileOperations.saveSettings(settings)
            withAnimation {
                showSavedBadge = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSavedBadge = false
                }
            }
        } catch {
            // Settings save failed — non-critical, user can retry
        }
    }

    private func saveAndValidate() {
        save()
        tokenValidationTask?.cancel()
        tokenValidationTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await validateToken()
        }
    }

    private func validateToken() async {
        let token = settings.vercelToken
        guard !token.isEmpty else {
            tokenStatus = .missing
            return
        }
        tokenStatus = .validating
        let teamId = settings.vercelTeamId
        guard let url = URL(string: "https://api.vercel.com/v9/projects?teamId=\(teamId)&limit=1") else {
            tokenStatus = .invalid
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            tokenStatus = status == 200 ? .valid : .invalid
        } catch {
            tokenStatus = .invalid
        }
    }

    private func detectToken() {
        let detection = FileOperations.detectVercelToken()
        if detection.found, let token = detection.token {
            settings.vercelToken = token
            saveAndValidate()
        } else {
            tokenStatus = .missing
        }
    }
}
