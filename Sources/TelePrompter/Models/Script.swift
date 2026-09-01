import Foundation

// MARK: - Script Model

struct TeleprompterScript: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), title: String = "Untitled Script", content: String = "") {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    mutating func updateContent(_ newContent: String) {
        content = newContent
        modifiedAt = Date()
    }

    mutating func rename(_ newTitle: String) {
        title = newTitle
        modifiedAt = Date()
    }

    // Computed word count from raw content
    var wordCount: Int {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var characterCount: Int {
        content.count
    }

    func estimatedDuration(wpm: Double) -> TimeInterval {
        guard wpm > 0 else { return 0 }
        return Double(wordCount) / wpm * 60.0
    }
}

// MARK: - Test Script

extension TeleprompterScript {
    static let testScript = TeleprompterScript(
        title: "Test Script",
        content: """
        Hello and welcome. This is a test of the teleprompter.
        
        I am going to demonstrate voice following. The application should follow this script as I speak.
        
        Today I want to show you how the system tracks your speech and automatically moves the teleprompter to match your position.
        
        You can speak naturally, and the teleprompter will keep pace with you. It does not matter if you say a word slightly differently, or if you pause for a moment.
        
        The system is designed to be forgiving of small differences between what is written and what you say.
        
        This concludes the test script. Thank you for trying the teleprompter.
        """
    )
}
