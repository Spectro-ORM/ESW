import Foundation
import ESWCompilerLib

@main
struct ESWCompilerCLI {
    static func main() {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            printUsageAndExit()
        }

        let inputPath = args[1]
        var outputPath: String?
        var emitSourceLocations = false

        var i = 2
        while i < args.count {
            switch args[i] {
            case "--output":
                guard i + 1 < args.count else {
                    fputs("error: --output requires a path argument\n", stderr)
                    exit(1)
                }
                outputPath = args[i + 1]
                i += 2
            case "--source-location":
                emitSourceLocations = true
                i += 1
            default:
                fputs("error: unknown argument '\(args[i])'\n", stderr)
                printUsageAndExit()
            }
        }

        do {
            let source = try String(contentsOfFile: inputPath, encoding: .utf8)
            let filename = URL(fileURLWithPath: inputPath).lastPathComponent
            let result = try compile(
                source: source,
                filename: filename,
                sourceFile: inputPath,
                emitSourceLocations: emitSourceLocations
            )

            if let outputPath {
                try result.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } else {
                print(result, terminator: "")
            }
        } catch let error as ESWTokenizerError {
            switch error {
            case .unterminatedTag(let file, let line, let column):
                fputs("\(file):\(line):\(column): error: unterminated ESW tag\n", stderr)
                exit(1)
            }
        } catch let error as ESWAssignsError {
            switch error {
            case .assignsNotFirst(let file, let line):
                fputs("\(file):\(line): error: assigns block must be the first tag in the file\n", stderr)
                exit(1)
            case .invalidDeclaration(let file, let line, let text):
                fputs("\(file):\(line): error: invalid declaration: \(text)\n", stderr)
                exit(1)
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func compile(
        source: String,
        filename: String,
        sourceFile: String,
        emitSourceLocations: Bool
    ) throws -> String {
        var tokenizer = Tokenizer(source: source, file: sourceFile)
        let rawTokens = try tokenizer.tokenize()
        let trimmedTokens = WhitespaceTrimmer.trim(rawTokens)
        let parameters = try AssignsParser.parse(tokens: trimmedTokens, file: sourceFile)
        let bodyTokens = trimmedTokens.filter {
            if case .assigns = $0 { return false }
            return true
        }
        let generator = CodeGenerator(
            tokens: bodyTokens,
            parameters: parameters,
            sourceFile: sourceFile,
            filename: filename,
            emitSourceLocations: emitSourceLocations
        )
        return generator.generate()
    }

    static func printUsageAndExit() -> Never {
        fputs("Usage: ESWCompilerCLI <input.esw> [--output <output.swift>] [--source-location]\n", stderr)
        exit(1)
    }
}
