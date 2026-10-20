import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

// Private, on-device AI. Nothing leaves the phone — Apple's built-in model via FoundationModels.
struct AIView: View {
    @State private var prompt = ""
    @State private var answer = ""
    @State private var thinking = false
    @State private var status = ""
    @FocusState private var focused: Bool

    var body: some View {
        Screen {
            Header(title: "SCRATCHPAD", sub: "on-device · private")
            Panel {
                Text(availabilityNote).font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            Panel {
                TextEditor(text: $prompt)
                    .focused($focused)
                    .font(Theme.mono(14))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("ask anything…").font(Theme.mono(14)).foregroundStyle(Theme.dim)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                HStack {
                    Button(thinking ? "…" : "RUN") { run() }
                        .font(Theme.mono(14, .bold))
                        .padding(.vertical, 8).padding(.horizontal, 20)
                        .background(Theme.acid).foregroundStyle(.black)
                        .disabled(thinking || prompt.isEmpty)
                    if !answer.isEmpty {
                        Button("clear") { answer = ""; prompt = "" }
                            .font(Theme.mono(13)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if !status.isEmpty { Text(status).font(Theme.mono(10)).foregroundStyle(Theme.dim) }
                }
            }
            if !answer.isEmpty {
                Panel {
                    Text(answer).font(Theme.mono(13)).textSelection(.enabled)
                }
            }
        }
        .onTapGesture { focused = false }
    }

    private var availabilityNote: String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Apple Intelligence model ready. Prompts run locally; no network."
            case .unavailable(.deviceNotEligible): return "This device can't run the on-device model."
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use this."
            case .unavailable(.modelNotReady): return "The model is still downloading. Try again shortly."
            case .unavailable: return "On-device model unavailable right now."
            }
        }
        #endif
        return "Needs iOS 26+ with Apple Intelligence."
    }

    private func run() {
        focused = false
        answer = ""
        status = ""
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                status = "model unavailable"; return
            }
            thinking = true
            let p = prompt
            Task {
                do {
                    let session = LanguageModelSession()
                    let start = Date()
                    let reply = try await session.respond(to: p)
                    answer = reply.content
                    status = String(format: "%.1fs · on-device", Date().timeIntervalSince(start))
                } catch {
                    status = "error"
                    answer = error.localizedDescription
                }
                thinking = false
            }
            return
        }
        #endif
        status = "unsupported"
    }
}
