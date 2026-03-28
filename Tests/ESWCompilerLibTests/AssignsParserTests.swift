import Testing
@testable import ESWCompilerLib

/// Helper: tokenize then parse assigns.
private func parseAssigns(_ source: String, file: String = "test.esw") throws -> [Parameter] {
    var tokenizer = Tokenizer(source: source, file: file)
    let tokens = try tokenizer.tokenize()
    return try AssignsParser.parse(tokens: tokens, file: file)
}

@Suite("AssignsParser")
struct AssignsParserTests {

    @Test func singleParameter() throws {
        let params = try parseAssigns("<%!\nvar user: User\n%>")
        #expect(params == [Parameter(name: "user", type: "User")])
    }

    @Test func multipleParameters() throws {
        let params = try parseAssigns("<%!\nvar user: User\nvar posts: [Post]\n%>")
        #expect(params == [
            Parameter(name: "user", type: "User"),
            Parameter(name: "posts", type: "[Post]"),
        ])
    }

    @Test func defaultValue() throws {
        let params = try parseAssigns("<%!\nvar isAdmin: Bool = false\n%>")
        #expect(params == [Parameter(name: "isAdmin", type: "Bool", defaultValue: "false")])
    }

    @Test func arrayType() throws {
        let params = try parseAssigns("<%!\nvar items: [String]\n%>")
        #expect(params == [Parameter(name: "items", type: "[String]")])
    }

    @Test func optionalType() throws {
        let params = try parseAssigns("<%!\nvar title: String?\n%>")
        #expect(params == [Parameter(name: "title", type: "String?")])
    }

    @Test func dictionaryTypeWithDefault() throws {
        let params = try parseAssigns("<%!\nvar config: [String: Int] = [:]\n%>")
        #expect(params == [Parameter(name: "config", type: "[String: Int]", defaultValue: "[:]")])
    }

    @Test func noAssigns() throws {
        let params = try parseAssigns("<h1>Hello</h1>")
        #expect(params.isEmpty)
    }

    @Test func assignsNotFirst() throws {
        #expect(throws: ESWAssignsError.self) {
            try parseAssigns("<p>hello</p>\n<%!\nvar x: Int\n%>")
        }
    }

    @Test func invalidDeclaration() throws {
        #expect(throws: ESWAssignsError.self) {
            try parseAssigns("<%!\nnot a var declaration\n%>")
        }
    }

    @Test func mixedParamsWithDefaults() throws {
        let params = try parseAssigns("<%!\nvar user: User\nvar posts: [Post]\nvar isAdmin: Bool = false\n%>")
        #expect(params == [
            Parameter(name: "user", type: "User"),
            Parameter(name: "posts", type: "[Post]"),
            Parameter(name: "isAdmin", type: "Bool", defaultValue: "false"),
        ])
    }

    @Test func stringDefaultValue() throws {
        let params = try parseAssigns("<%!\nvar title: String = \"Hello World\"\n%>")
        #expect(params == [Parameter(name: "title", type: "String", defaultValue: "\"Hello World\"")])
    }
}
