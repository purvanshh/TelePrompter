import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sessionController: SessionController

    @State private var currentPage: Int = 0
    @State private var micPermissionResult: String? = nil
    @State private var isRequestingMic: Bool = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "tv.badge.wifi",
            title: "Welcome to TelePrompter",
            subtitle: "Your script follows your voice",
            body: """
            TelePrompter displays your script in a floating overlay while you record. \
            As you speak, it automatically follows your position in the script — no \
            manual scrolling required.
            """,
            action: nil
        ),
        OnboardingPage(
            icon: "mic.fill",
            title: "Microphone Access",
            subtitle: "Required for voice following",
            body: """
            TelePrompter listens to your microphone locally using Apple's Speech \
            Recognition. Your audio is processed on-device when possible — it is \
            never uploaded.
            """,
            action: "Allow Microphone Access"
        ),
        OnboardingPage(
            icon: "video.slash.fill",
            title: "Screen Recording Protection",
            subtitle: "Teleprompter stays hidden from supported recordings",
            body: """
            The teleprompter overlay uses macOS window exclusion (NSWindow.sharingType = .none) \
            to hide itself from QuickTime Player recordings and macOS Screenshot. \
            
            OBS Studio "Display Capture" may still show the window. Use OBS "Window Capture" \
            mode for best results.
            """,
            action: nil
        ),
        OnboardingPage(
            icon: "doc.text.fill",
            title: "Load Your Script",
            subtitle: "Paste, import, or use a test script",
            body: """
            Go to Scripts to create or import your script. \
            Then open the Teleprompter tab, load your script, and click \
            "Start Following" to begin.
            
            A test script is available if you want to try it first.
            """,
            action: nil
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { idx in
                    pageContent(pages[idx], index: idx)
                        .tag(idx)
                }
            }
            .tabViewStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            HStack {
                Button("Skip") {
                    settings.hasCompletedOnboarding = true
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                // Page dots
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        settings.hasCompletedOnboarding = true
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - Page content

    private func pageContent(_ page: OnboardingPage, index: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title2.bold())
                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            // Special handling for mic permission page
            if index == 1 {
                micPermissionButton
            }

            if let result = micPermissionResult, index == 1 {
                Label(result, systemImage: result.contains("granted") ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.contains("granted") ? .green : .red)
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var micPermissionButton: some View {
        Button {
            isRequestingMic = true
            Task {
                let granted = await sessionController.audioInputService.requestMicPermission()
                micPermissionResult = granted ? "Microphone access granted" : "Access denied — enable in System Settings → Privacy & Security → Microphone"
                isRequestingMic = false
            }
        } label: {
            Label(isRequestingMic ? "Requesting…" : "Allow Microphone Access",
                  systemImage: "mic.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isRequestingMic || sessionController.audioInputService.micPermissionGranted)
    }
}

// MARK: - OnboardingPage model

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let body: String
    let action: String?
}
