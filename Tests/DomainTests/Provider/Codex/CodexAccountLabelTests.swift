import Testing
@testable import Domain

@Suite("Codex menu bar email labels")
struct CodexAccountLabelTests {
    @Test func `short addresses remain intact`() {
        #expect(CodexAccountLabel.compact("a@example.com", among: ["a@example.com"]) == "a@example.com")
    }

    @Test func `abbreviated collisions retain full emails`() {
        let emails = ["same-long-prefix-one@example.com", "same-long-prefix-two@example.com"]
        for email in emails {
            #expect(CodexAccountLabel.compact(email, among: emails) == email)
        }
    }
}
