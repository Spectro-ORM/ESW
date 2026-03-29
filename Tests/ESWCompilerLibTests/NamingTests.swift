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

    @Test func doubleExtensionHTML() {
        #expect(Naming.functionName(from: "layout.html.esw") == "renderLayout")
    }

    @Test func doubleExtensionHTMLSnakeCase() {
        #expect(Naming.functionName(from: "user_profile.html.esw") == "renderUserProfile")
    }

    @Test func doubleExtensionPartial() {
        #expect(Naming.functionName(from: "_nav_bar.html.esw") == "renderNavBar")
    }

    @Test func doubleExtensionBufferName() {
        #expect(Naming.bufferFunctionName(from: "_card.html.esw") == "_renderCardBuffer")
    }

    @Test func doubleExtensionIsPartial() {
        #expect(Naming.isPartial("_header.html.esw") == true)
        #expect(Naming.isPartial("header.html.esw") == false)
    }
}
