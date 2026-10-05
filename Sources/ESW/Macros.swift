// MARK: - ESW Compile-Time Rendering Macros

/// Associates a top-level view struct with a template relative to this Swift
/// file. ESWBuildPlugin generates `render()` in an extension, where the struct's
/// properties and helpers are in scope. Both files are tracked build inputs.
///
/// Requires ESWBuildPlugin on the target. Referenced members must be accessible
/// from another source file (internal, package or public).
@attached(extension, conformances: ESWView)
public macro ESWTemplate(_ path: String) =
    #externalMacro(module: "ESWMacros", type: "ESWTemplateMacro")

/// Renders a `.esw` or `.heex` template file at compile time, returning a `String`.
/// The file extension selects text or HTML-aware syntax.
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
/// The result is framework-independent HTML. Pass it to your server's HTML response API.
/// File lookup checks at most six directory levels. The file read does not establish
/// a SwiftPM build dependency: use `ESWBuildPlugin` for reliable template-only rebuilds.
/// Compile-time file reads may require `swift build --disable-sandbox`.
///
/// - Parameter templatePath: A literal relative or absolute template path.
/// - Returns: Complete HTML. Even a `.live.heex` file returns `String` through this macro.
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

/// HTML-aware ESW: balanced tags, `{expression}`, dynamic attributes,
/// and `:if` / `:for` directives using Swift expressions.
///
/// ```swift
/// let names = ["Ada", "Grace"]
/// let html = #heex("<ul><li :for={name in names}>{name}</li></ul>")
/// ```
///
/// The argument must be a string literal without Swift string interpolation.
/// Values come from the surrounding Swift scope. Use `{value}` for dynamic text
/// and `title={value}` for dynamic attributes.
@freestanding(expression)
public macro heex(_ template: String) -> String =
    #externalMacro(module: "ESWMacros", type: "InlineESWMacro")

/// Compiles HEEx into a structured snapshot suitable for live DOM updates.
///
/// Authoring and escaping rules match ``heex(_:)``. The result separates literal
/// HTML from dynamic strings; ``ESWLiveRender/html`` produces a complete page
/// fragment and ``ESWLiveRender/diff(to:)`` computes output changes.
/// The `ESWLive` module supplies state and event handling separately.
@freestanding(expression)
public macro live(_ template: String) -> ESWLiveRender =
    #externalMacro(module: "ESWMacros", type: "InlineESWMacro")
