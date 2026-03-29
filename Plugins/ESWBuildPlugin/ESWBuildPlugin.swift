import Foundation
import PackagePlugin

@main
struct ESWBuildPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }

        let eswFiles = target.sourceFiles.filter {
            $0.type == .unknown && $0.url.pathExtension == "esw"
        }
        let tool = try context.tool(named: "ESWCompilerCLI")

        return eswFiles.map { file in
            // Strip all extensions: "layout.html.esw" → "layout"
            var stem = file.url.deletingPathExtension().lastPathComponent
            if let dotIndex = stem.firstIndex(of: ".") {
                stem = String(stem[..<dotIndex])
            }
            let outputName = "render_\(stem).swift"
            let output = context.pluginWorkDirectoryURL.appending(path: outputName)

            return .buildCommand(
                displayName: "Compiling \(file.url.lastPathComponent)",
                executable: tool.url,
                arguments: [
                    file.url.path(percentEncoded: false),
                    "--output", output.path(percentEncoded: false),
                    "--source-location"
                ],
                inputFiles: [file.url],
                outputFiles: [output]
            )
        }
    }
}
