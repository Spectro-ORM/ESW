import PackagePlugin

@main
struct ESWBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let templates = target.sourceFiles.filter {
            ["esw", "heex"].contains($0.url.pathExtension)
        }.map(\.url).sorted { $0.path < $1.path }
        guard !templates.isEmpty else { return [] }
        let tool = try context.tool(named: "ESWCompilerCLI")
        let output = context.pluginWorkDirectoryURL.appending(path: "ESWTemplates.swift")
        return [.buildCommand(
            displayName: "Compiling ESW templates for \(target.name)",
            executable: tool.url,
            arguments: ["--batch", "--root", target.directoryURL.path,
                        "--output", output.path, "--source-location"] + templates.map(\.path),
            inputFiles: templates,
            outputFiles: [output]
        )]
    }
}
