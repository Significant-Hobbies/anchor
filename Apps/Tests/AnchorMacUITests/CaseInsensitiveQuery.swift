import XCTest

extension XCUIElementQuery {
    /// The UI voice is lowercase; match identifiers, labels and values without regard to case.
    func ci(_ text: String) -> XCUIElement {
        matching(
            NSPredicate(
                format: "identifier ==[c] %@ OR label ==[c] %@ OR title ==[c] %@ OR placeholderValue ==[c] %@ OR value ==[c] %@",
                text, text, text, text, text)
        ).firstMatch
    }
}
