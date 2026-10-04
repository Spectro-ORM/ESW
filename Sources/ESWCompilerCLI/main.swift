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
            let templates = try options.inputs.map { path in
                TemplateSource(name: try options.templateName(for: path),
                               source: try String(contentsOfFile: path, encoding: .utf8), sourceFile: path)
            }
            let result: String
            if options.batch {
                result = try compileTemplates(templates, emitSourceLocations: options.sourceLocations)
            } else {
                let template = templates[0]
                result = try compile(source: template.source, filename: template.name, sourceFile: template.sourceFile,
                                     emitSourceLocations: options.sourceLocations, syntax: options.syntax)
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
