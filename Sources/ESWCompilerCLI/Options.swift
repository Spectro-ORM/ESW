import Foundation
import ESWCompilerLib

struct Options {
    static let usage = """
    Usage: ESWCompilerCLI <input.esw|input.heex> [--output <file.swift>] [--source-location] [--heex]
           ESWCompilerCLI --batch --root <target-directory> --output <file.swift> <templates...>
    """
    var inputs: [String] = []
    var output: String?
    var root: String?
    var sourceLocations = false
    var syntax: TemplateSyntax?
    var batch = false
    var help = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output", "--root":
                guard index + 1 < arguments.count else {
                    throw ESWTemplateError("error: \(argument) requires a path")
                }
                index += 1
                if argument == "--output" { output = arguments[index] }
                else { root = arguments[index] }
            case "--source-location": sourceLocations = true
            case "--heex": syntax = .heex
            case "--batch": batch = true
            case "--help", "-h": help = true
            default:
                guard !argument.hasPrefix("--") else {
                    throw ESWTemplateError("error: unknown argument '\(argument)'")
                }
                inputs.append(argument)
            }
            index += 1
        }
        if help { return }
        guard !inputs.isEmpty, batch || inputs.count == 1 else {
            throw ESWTemplateError("error: supply one template, or use --batch for multiple templates\n" + Self.usage)
        }
        guard !batch || syntax == nil else {
            throw ESWTemplateError("error: --batch selects syntax by file extension; --heex is for single-file compilation")
        }
    }

    func templateName(for path: String) throws -> String {
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard let root else { return file.lastPathComponent }
        let directory = URL(fileURLWithPath: root).standardizedFileURL
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard file.path.hasPrefix(prefix) else {
            throw ESWTemplateError("error: template '\(path)' is outside root '\(root)'")
        }
        var name = String(file.path.dropFirst(prefix.count))
        if name.hasPrefix("Views/") { name = String(name.dropFirst(6)) }
        return name
    }
}
