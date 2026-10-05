/// One template with a logical path relative to its template root.
public struct TemplateSource: Sendable {
    /// Logical path, such as `users/index.heex`, used to derive generated names.
    public let name: String
    /// Complete template text.
    public let source: String
    /// Original path used for diagnostic locations.
    public let sourceFile: String
    /// Companion view metadata, when generating an instance method.
    public let view: TemplateView?

    /// Describes a template that has already been loaded by the caller.
    public init(name: String, source: String, sourceFile: String, view: TemplateView? = nil) {
        self.name = name
        self.source = source
        self.sourceFile = sourceFile
        self.view = view
    }
}

/// A human-readable error for template naming, batching, or view validation.
public struct ESWTemplateError: Error, Sendable, CustomStringConvertible {
    /// The diagnostic text, including source location when available.
    public let description: String

    /// Creates a diagnostic from formatted text.
    public init(_ description: String) { self.description = description }
}

/// Compiles a target as one Swift file, checking names before generating output.
/// Keeping this here makes the CLI and build plugin use identical naming rules.
///
/// Templates are sorted by logical name. Colliding function names or typed-view
/// `render()` methods are rejected before output is returned. This function does
/// not read or write files; callers can atomically write its result after success.
/// - Parameters:
///   - templates: Loaded templates and optional typed-view metadata.
///   - emitSourceLocations: Whether to map generated code to original template paths.
/// - Returns: One string containing the generated Swift declarations.
/// - Throws: A naming collision or a diagnostic from an individual template.
public func compileTemplates(_ templates: [TemplateSource], emitSourceLocations: Bool = true) throws -> String {
    let sorted = templates.sorted { $0.name < $1.name }
    var names: [String: String] = [:]
    for template in sorted {
        let name = Naming.functionName(from: template.name)
        guard name != "render", name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              !template.name.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw ESWTemplateError("\(template.sourceFile):1:1: error: invalid template name '\(template.name)'")
        }
        let symbol = template.view.map { "\($0.typeName.filter { $0 != "`" }).render()" } ?? name
        if let previous = names[symbol] {
            throw ESWTemplateError("\(template.sourceFile):1:1: error: templates '\(previous)' and '\(template.name)' both generate \(symbol). Rename one template or its view.")
        }
        names[symbol] = template.name
    }
    return try sorted.map { template in
        try compile(source: template.source, filename: template.name, sourceFile: template.sourceFile,
                    emitSourceLocations: emitSourceLocations, view: template.view)
    }.joined(separator: "\n")
}
