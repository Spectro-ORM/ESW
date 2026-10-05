import Foundation
import ESWCompilerLib

@main
struct ESWCompilerCLI {
    static func main() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.help {
                print(Options.usage)
                return
            }
            let inputPaths = Set(options.inputs.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
            var views: [String: TemplateView] = [:]
            for sourceFile in options.viewSources {
                let source = try String(contentsOfFile: sourceFile, encoding: .utf8)
                for view in try TemplateView.discover(source: source, sourceFile: sourceFile) {
                    let path = URL(fileURLWithPath: sourceFile).deletingLastPathComponent()
                        .appendingPathComponent(view.templatePath!).standardizedFileURL.path
                    guard inputPaths.contains(path) else {
                        throw ESWTemplateError("\(sourceFile):1:1: error: template '\(view.templatePath!)' is missing or is not a template input in this target")
                    }
                    if let previous = views[path] {
                        throw ESWTemplateError("\(sourceFile):1:1: error: template '\(view.templatePath!)' is already associated with '\(previous.typeName)' in '\(previous.sourceFile)'")
                    }
                    views[path] = view
                }
            }
            let templates = try options.inputs.map { path in
                let view = views[URL(fileURLWithPath: path).standardizedFileURL.path]
                return TemplateSource(name: try options.templateName(for: path),
                                      source: try String(contentsOfFile: path, encoding: .utf8),
                                      sourceFile: path, view: view)
            }
            let result: String
            if options.batch {
                result = try compileTemplates(templates, emitSourceLocations: options.sourceLocations)
            } else {
                let template = templates[0]
                result = try compile(source: template.source, filename: template.name, sourceFile: template.sourceFile,
                                     emitSourceLocations: options.sourceLocations, syntax: options.syntax, view: template.view)
            }
            if let output = options.output {
                try result.write(toFile: output, atomically: true, encoding: .utf8)
            } else {
                print(result, terminator: "")
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
