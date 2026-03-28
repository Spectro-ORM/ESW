import Testing
@testable import ESWCompilerLib

@Suite("Naming")
struct NamingTests {

    @Test func userProfile() {
        #expect(Naming.functionName(from: "user_profile.esw") == "renderUserProfile")
    }

    @Test func layout() {
        #expect(Naming.functionName(from: "layout.esw") == "renderLayout")
    }

    @Test func partialUserCard() {
        #expect(Naming.functionName(from: "_user_card.esw") == "renderUserCard")
    }

    @Test func index() {
        #expect(Naming.functionName(from: "index.esw") == "renderIndex")
    }

    @Test func bufferFunctionName() {
        #expect(Naming.bufferFunctionName(from: "_user_card.esw") == "_renderUserCardBuffer")
    }

    @Test func isPartialTrue() {
        #expect(Naming.isPartial("_user_card.esw") == true)
    }

    @Test func isPartialFalse() {
        #expect(Naming.isPartial("user_profile.esw") == false)
    }

    @Test func multipleUnderscores() {
        #expect(Naming.functionName(from: "__private_view.esw") == "renderPrivateView")
    }
}
