// MARK: - ESW Compile-Time Rendering Macros

/// Renders a `.esw` template file at compile time, returning the result as a `String`.
///
/// The template file is located by walking up the directory tree from the invoking
/// source file, checking `Views/<name>` and `<name>` directly at each level.
///
/// Variables referenced inside the template are captured from the **surrounding scope**
/// at the call site — no explicit bindings are declared. If a variable is missing
/// or has the wrong type, the expansion fails with a standard Swift compiler error
/// pointing directly at the `#render(...)` call.
///
/// ```swift
/// // donut_list.esw declares: <%! var donuts: [Donut] %>
/// let donuts = try await db.query(Donut.self).all()
///
/// // donuts is in scope, so the expansion compiles cleanly:
/// return conn.html(#render("donut_list.esw"))
/// ```
///
/// Works naturally with ``Connection/respondTo(html:json:)``:
/// ```swift
/// return try conn.respondTo(
///     html: { conn.html(#render("donut_list.esw")) },
///     json: { try conn.json(value: donuts) }
/// )
/// ```
@freestanding(expression)
public macro render(_ templatePath: String) -> String =
    #externalMacro(module: "ESWMacros", type: "RenderMacro")

/// Renders an inline ESW template string at compile time, returning the result as a `String`.
///
/// Useful for small, co-located templates that don't warrant a dedicated `.esw` file.
/// Variables are captured from the surrounding scope, exactly like `#render`.
///
/// Swift string interpolations (`\(...)`) inside the literal are a compile error —
/// use ESW output tags (`<%= ... %>`) instead.
///
/// ```swift
/// let badge = #esw("""
///     <span class="badge"><%= count %></span>
///     """)
///
/// return conn.html(#esw("""
///     <ul>
///       <% for donut in donuts { %>
///         <li><%= donut.name %> — $<%= donut.price %></li>
///       <% } %>
///     </ul>
///     """))
/// ```
@freestanding(expression)
public macro esw(_ template: String) -> String =
    #externalMacro(module: "ESWMacros", type: "InlineESWMacro")
