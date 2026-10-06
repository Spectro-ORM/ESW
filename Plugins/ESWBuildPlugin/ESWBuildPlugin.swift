import PackagePlugin

@main
struct ESWBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let templates = target.sourceFiles.filter {
            ["esw", "hesw", "heex"].contains($0.url.pathExtension)
        }.map(\.url).sorted { $0.path < $1.path }
        let viewSources = target.sourceFiles.map(\.url).filter {
            $0.pathExtension == "swift"
        }.sorted { $0.path < $1.path }
        guard !templates.isEmpty || !viewSources.isEmpty else { return [] }
        let tool = try context.tool(named: "ESWCompilerCLI")
        let output = context.pluginWorkDirectoryURL.appending(path: "ESWTemplates.swift")
        return [.buildCommand(
            displayName: "Compiling ESW templates for \(target.name)",
            executable: tool.url,
            arguments: ["--batch", "--root", target.directoryURL.path,
                        "--output", output.path, "--source-location"]
                + viewSources.flatMap { ["--view-source", $0.path] } + templates.map(\.path),
            inputFiles: templates + viewSources,
            outputFiles: [output]
        )]
    }
}
