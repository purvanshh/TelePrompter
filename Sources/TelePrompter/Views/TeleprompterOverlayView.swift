import SwiftUI
import AppKit

// MARK: - TeleprompterOverlayView
// The floating overlay window content — the core display the user reads from.

struct TeleprompterOverlayView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: TeleprompterState

    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(settings.backgroundOpacity))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top drag handle + minimal controls
                if showControls && settings.readingMode != .recording {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Script text
                scriptScrollView
                    .padding(.horizontal, 16)
                    .padding(.vertical, showControls ? 8 : 0)

                // Bottom status bar
                if showControls && settings.readingMode != .recording {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(x: settings.mirrorMode ? -1 : 1, y: 1)
        .onHover { hovering in
            handleHover(hovering)
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    // MARK: - Script scroll view

    private var scriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 8) {
                    ForEach(state.document.sentences) { sentence in
                        sentenceView(sentence)
                            .id(sentence.id)
                    }

                    if state.followingState == .complete {
                        completionMessage
                    }

                    // Bottom padding so last sentence can scroll to center
                    Color.clear.frame(height: 200)
                }
                .frame(maxWidth: .infinity, alignment: textFrameAlignment)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: state.currentSentenceIndex) { _, newIdx in
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    // MARK: - Sentence rendering

    @ViewBuilder
    private func sentenceView(_ sentence: ScriptSentence) -> some View {
        let isActive = sentence.id == state.currentSentenceIndex
        let isPast   = sentence.id < state.currentSentenceIndex

        Group {
            switch settings.highlightMode {
            case .none:
                Text(sentence.text)
                    .foregroundStyle(.white.opacity(settings.textOpacity))

            case .sentence:
                Text(sentence.text)
                    .foregroundStyle(isActive
                        ? Color.white.opacity(settings.textOpacity)
                        : Color.white.opacity(settings.textOpacity * (isPast ? 0.35 : 0.6)))
                    .padding(.horizontal, isActive ? 10 : 0)
                    .background(
                        isActive
                        ? RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.12))
                        : nil
                    )

            case .word:
                wordHighlightedText(sentence, isActive: isActive, isPast: isPast)

            case .progress:
                Text(sentence.text)
                    .foregroundStyle(isPast
                        ? Color.green.opacity(0.7)
                        : isActive
                            ? Color.white.opacity(settings.textOpacity)
                            : Color.white.opacity(settings.textOpacity * 0.5))
            }
        }
        .font(.custom(settings.fontName,
                      size: settings.fontSize,
                      relativeTo: .body))
        .fontWeight(settings.fontWeightValue)
        .lineSpacing(settings.fontSize * (settings.lineSpacing - 1))
        .multilineTextAlignment(settings.resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: textFrameAlignment)
        .contentShape(Rectangle())
        .onTapGesture {
            state.jumpToSentence(sentence.id)
        }
    }

    // MARK: - Word-level highlighting

    private func wordHighlightedText(_ sentence: ScriptSentence, isActive: Bool, isPast: Bool) -> some View {
        let words = sentence.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var text = Text("")
        for (i, word) in words.enumerated() {
            let wordIdx = sentence.wordRange.lowerBound + i
            let isCurrentWord = isActive && wordIdx == state.currentWordIndex
            let isSpokenWord  = wordIdx < state.currentWordIndex

            let chunk = Text(word + " ")
                .foregroundStyle(
                    isCurrentWord ? Color.yellow :
                    isSpokenWord  ? Color.white.opacity(0.4) :
                    isActive      ? Color.white :
                    Color.white.opacity(0.5)
                )
            text = text + chunk
        }
        return text
            .font(.custom(settings.fontName, size: settings.fontSize, relativeTo: .body))
            .fontWeight(settings.fontWeightValue)
    }

    // MARK: - Top bar (drag handle + minimal controls)

    private var topBar: some View {
        HStack {
            // Drag area indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Bottom status bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Following state indicator
            Label(state.followingState.displayText,
                  systemImage: state.followingState.symbolName)
                .font(.caption)
                .foregroundStyle(statusColor)

            Spacer()

            // Progress
            if settings.showProgress && state.document.totalWords > 0 {
                Text("\(Int(state.progressFraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Audio level
            AudioLevelView(level: state.audioLevel)
                .frame(width: 30, height: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Completion message

    private var completionMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("Script Complete")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private var textFrameAlignment: Alignment {
        switch settings.textAlignment {
        case 0: return .leading
        case 1: return .center
        case 2: return .trailing
        default: return .leading
        }
    }

    private var statusColor: Color {
        switch state.followingState {
        case .following:     return .green
        case .listening:     return .blue
        case .paused:        return .yellow
        case .lowConfidence: return .orange
        case .error:         return .red
        case .micUnavailable, .speechUnavailable: return .red
        case .complete:      return .green
        default:             return .white.opacity(0.5)
        }
    }

    private func handleHover(_ hovering: Bool) {
        controlsTimer?.invalidate()
        if hovering {
            withAnimation { showControls = true }
        } else {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                Task { @MainActor in
                    if self.settings.readingMode == .recording {
                        withAnimation { self.showControls = false }
                    }
                }
            }
        }
    }
}

// MARK: - AudioLevelView

struct AudioLevelView: View {
    var level: Float
    private let barCount = 8

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let threshold = Float(i) / Float(barCount)
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(index: i))
                    .opacity(level >= threshold ? 1.0 : 0.2)
                    .frame(width: 2, height: CGFloat(5 + i))
            }
        }
        .frame(height: 12, alignment: .bottom)
    }

    private func barColor(index: Int) -> Color {
        if index < barCount / 2 { return .green }
        if index < barCount * 3 / 4 { return .yellow }
        return .red
    }
}
