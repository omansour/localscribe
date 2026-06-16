import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var state: AppState

    private let languages: [(label: String, code: String)] = [
        ("Auto (Parakeet)", ""),
        ("French (fr)", "fr"),
        ("English (en)", "en"),
        ("Spanish (es)", "es"),
        ("German (de)", "de"),
        ("Italian (it)", "it"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            permissionRow
            Divider()
            recordingSection
            if state.lastRecording != nil {
                Divider()
                transcribeSection
            }
            if !state.log.isEmpty {
                Divider()
                logSection
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { state.refreshPermissions() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
            Text("LocalScribe Recorder").font(.headline)
            Spacer()
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 16) {
            permissionBadge(title: "Mic", ok: state.micAuthorized) {
                state.requestMicPermission()
            }
            permissionBadge(title: "System", ok: state.systemAuthorized) {
                state.requestSystemPermission()
            }
            Spacer()
        }
    }

    private func permissionBadge(title: String, ok: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            if !ok {
                Button("Grant", action: action)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state.phase {
            case .recording:
                HStack {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Recording  \(timeString(state.elapsed))").monospacedDigit()
                }
                Button("Stop") { state.stopRecording() }
                    .keyboardShortcut(.return)
            case .mixing:
                ProgressView("Mixing audio…")
            default:
                Button {
                    state.startRecording()
                } label: {
                    Label("Start recording", systemImage: "record.circle")
                }
                .disabled(!state.micAuthorized)
                if !state.micAuthorized {
                    Text("Microphone permission required.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transcribeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rec = state.lastRecording {
                HStack {
                    Text(rec.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Reveal") { state.revealRecording() }.buttonStyle(.link).font(.caption)
                }
            }
            Picker("Language", selection: $state.language) {
                ForEach(languages, id: \.code) { Text($0.label).tag($0.code) }
            }
            Picker("Speakers", selection: $state.speakers) {
                Text("Auto").tag(-1)
                ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
            }

            if state.phase == .transcribing {
                ProgressView("Transcribing…")
            } else {
                Button {
                    state.transcribe()
                } label: {
                    Label("Transcribe", systemImage: "text.bubble")
                }
                .disabled(state.isBusy)
            }
        }
    }

    private var logSection: some View {
        ScrollView {
            Text(state.log)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: 120)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button("Open output folder") { state.openOutputFolder() }
                .buttonStyle(.link)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
