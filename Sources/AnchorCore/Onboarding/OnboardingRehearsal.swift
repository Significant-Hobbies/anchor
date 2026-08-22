import Foundation

/// Ephemeral practice for Anchor's park-and-return loop.
///
/// This is deliberately a plain value, not a SwiftData model or sync record.
/// A rehearsal thought exists only while its view is alive and is discarded as
/// soon as the return receipt is created.
public struct OnboardingRehearsal: Equatable, Sendable {
    public enum Step: Int, Equatable, Sendable {
        case goal
        case focusing
        case capture
        case returned
    }

    public struct ReturnReceipt: Equatable, Sendable {
        public var goal: String
        public var recoveredThought: String

        public init(goal: String, recoveredThought: String) {
            self.goal = goal
            self.recoveredThought = recoveredThought
        }
    }

    public private(set) var step: Step
    public private(set) var goal: String
    public private(set) var thought: String
    public private(set) var receipt: ReturnReceipt?

    public init(step: Step = .goal, goal: String = "", thought: String = "", receipt: ReturnReceipt? = nil) {
        self.step = step
        self.goal = goal
        self.thought = thought
        self.receipt = receipt
    }

    public mutating func begin(goal: String) -> Bool {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        self.goal = trimmed
        thought = ""
        receipt = nil
        step = .focusing
        return true
    }

    public mutating func openCapture() {
        guard step == .focusing else { return }
        step = .capture
    }

    public mutating func updateThought(_ value: String) {
        thought = value
    }

    @discardableResult
    public mutating func parkAndReturn() -> ReturnReceipt? {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard step == .capture, !trimmed.isEmpty else { return nil }
        let receipt = ReturnReceipt(goal: goal, recoveredThought: trimmed)
        self.receipt = receipt
        thought = ""
        step = .returned
        return receipt
    }

    public mutating func practiceAgain() {
        thought = ""
        receipt = nil
        step = .focusing
    }
}
