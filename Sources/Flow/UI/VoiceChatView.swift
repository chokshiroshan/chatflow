import SwiftUI

/// Floating window for voice chat mode.
/// Shows the conversation transcript in real-time.
struct VoiceChatView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var transcript: [ChatMessage] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(coordinator.state == .recording ? .red : (coordinator.state == .speaking ? .green : .gray))
                    .frame(width: 10, height: 10)
                Text(coordinator.state == .recording ? "Listening..." : (coordinator.state == .speaking ? "Speaking..." : "Voice Chat"))
                    .font(.headline)
                Spacer()
                Button("×") {
                    coordinator.stopVoiceChat()
                }
                .buttonStyle(.plain)
                .font(.title2)
            }
            .padding()

            Divider()

            // Transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcript) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: transcript.count) { _, _ in
                    if let last = transcript.last {
                        withAnimation { proxy.scrollTo(last.id) }
                    }
                }
            }

            Divider()

            // Controls
            HStack {
                if coordinator.voiceChatActive {
                    Button("Stop") {
                        coordinator.stopVoiceChat()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Interrupt") {
                        coordinator.interruptVoiceChat()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onReceive(coordinator.$userTranscript) { text in
            if !text.isEmpty {
                updateOrCreateMessage(role: .user, text: text)
            }
        }
        .onReceive(coordinator.$assistantTranscript) { text in
            if !text.isEmpty {
                updateOrCreateMessage(role: .assistant, text: text)
            }
        }
    }

    private func updateOrCreateMessage(role: ChatMessage.Role, text: String) {
        if let lastIdx = transcript.indices.last,
           transcript[lastIdx].role == role && !transcript[lastIdx].final {
            transcript[lastIdx].text = text
        } else {
            // Finalize previous message
            if let lastIdx = transcript.indices.last {
                transcript[lastIdx].final = true
            }
            transcript.append(ChatMessage(role: role, text: text))
        }
    }
}

// MARK: - Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    var final: Bool = false

    enum Role {
        case user
        case assistant
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    message.role == .user
                    ? Color.accentColor.opacity(0.2)
                    : Color.gray.opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role == .assistant { Spacer() }
        }
    }
}
