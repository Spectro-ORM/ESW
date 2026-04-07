import Testing
@testable import ESWCompilerLib

@Suite("Integration")
struct IntegrationTests {

    @Test func fullSpecExample() throws {
        let source = """
        <%!
        var user: User
        var posts: [Post]
        %>
        <div class="profile">
          <h1><%= user.name %></h1>
          <p class="email"><%= user.email %></p>
          <% if user.isAdmin { %>
            <span class="badge">Admin</span>
          <% } %>
          <ul class="posts">
            <% for post in posts { %>
              <li>
                <a href="/posts/<%= post.id %>"><%= post.title %></a>
              </li>
            <% } %>
          </ul>
        </div>
        """

        let output = try compile(
            source: source,
            filename: "user_profile.esw",
            sourceFile: "Sources/App/Views/user_profile.esw",
            emitSourceLocations: false
        )

        // Function name
        #expect(output.contains("func renderUserProfile("))
        // Parameters
        #expect(output.contains("user: User"))
        #expect(output.contains("posts: [Post]"))
        // Return type
        #expect(output.contains("-> String"))
        // Escaped output
        #expect(output.contains("_buf.appendEscaped(user.name)"))
        #expect(output.contains("_buf.appendEscaped(user.email)"))
        #expect(output.contains("_buf.appendEscaped(post.id)"))
        #expect(output.contains("_buf.appendEscaped(post.title)"))
        // Control flow
        #expect(output.contains("if user.isAdmin {"))
        #expect(output.contains("for post in posts {"))
        // HTML content
        #expect(output.contains("profile"))
        #expect(output.contains("badge"))
        #expect(output.contains("Admin"))
        // Header
        #expect(output.contains("// AUTO-GENERATED"))
        #expect(!output.contains("import Nexus"))
        #expect(output.contains("import ESW"))
        #expect(output.contains("_buf.finalize()"))
    }

    @Test func partialEndToEnd() throws {
        let source = """
        <%!
        var user: User
        %>
        <div class="card">
          <h2><%= user.name %></h2>
        </div>
        """

        let output = try compile(
            source: source,
            filename: "_user_card.esw",
            sourceFile: "Sources/App/Views/_user_card.esw",
            emitSourceLocations: false
        )

        // Single String-returning function
        #expect(output.contains("func renderUserCard("))
        #expect(output.contains("user: User"))
        #expect(output.contains(") -> String {"))
        #expect(output.contains("return _buf.finalize()"))
    }

    @Test func emptyTemplate() throws {
        let output = try compile(
            source: "",
            filename: "empty.esw",
            sourceFile: "empty.esw",
            emitSourceLocations: false
        )
        #expect(output.contains("func renderEmpty() -> String {"))
        #expect(output.contains("return _buf.finalize()"))
    }

    @Test func sourceLocationsPresent() throws {
        let output = try compile(
            source: "<%= x %>",
            filename: "test.esw",
            sourceFile: "Sources/test.esw",
            emitSourceLocations: true
        )
        #expect(output.contains("#sourceLocation(file: \"Sources/test.esw\""))
        #expect(output.contains("#sourceLocation()"))
    }

    @Test func layoutPattern() throws {
        let source = """
        <%!
        var title: String
        var content: String
        %>
        <!DOCTYPE html>
        <html>
          <head>
            <title><%= title %></title>
          </head>
          <body>
            <%== content %>
          </body>
        </html>
        """

        let output = try compile(
            source: source,
            filename: "layout.esw",
            sourceFile: "Sources/App/Views/layout.esw",
            emitSourceLocations: false
        )

        #expect(output.contains("func renderLayout("))
        #expect(output.contains("title: String"))
        #expect(output.contains("content: String"))
        #expect(output.contains("_buf.appendEscaped(title)"))
        // Raw output for content (already escaped by partial)
        #expect(output.contains("_buf.appendUnsafe(content)"))
        #expect(!output.contains("_buf.appendEscaped(content)"))
    }
}
