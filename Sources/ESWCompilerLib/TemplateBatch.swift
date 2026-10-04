/// One template with a logical path relative to its template root.
public struct TemplateSource: Sendable {
    public let name: String
    public let source: String
    public let sourceFile: String

    public init(name: String, source: String, sourceFile: String) {
        self.name = name
        self.source = source
        self.sourceFile = sourceFile
    }
}

public struct ESWTemplateError: Error, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) { self.description = description }
}

/// Compiles a target as one Swift file, checking names before generating output.
/// Keeping this here makes the CLI and build plugin use identical naming rules.
public func compileTemplates(_ templates: [TemplateSource], emitSourceLocations: Bool = true) throws -> String {
    let sorted = templates.sorted { $0.name < $1.name }
    var names: [String: String] = [:]
    for template in sorted {
        let name = Naming.functionName(from: template.name)
        guard name != "render", name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              !template.name.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw ESWTemplateError("\(template.sourceFile):1:1: error: invalid template name '\(template.name)'")
        }
        if let previous = names[name] {
            throw ESWTemplateError("\(template.sourceFile):1:1: error: templates '\(previous)' and '\(template.name)' both generate \(name). Rename one template.")
        }
        names[name] = template.name
    }
    return try sorted.map { template in
        try compile(source: template.source, filename: template.name, sourceFile: template.sourceFile,
                    emitSourceLocations: emitSourceLocations)
    }.joined(separator: "\n")
}
