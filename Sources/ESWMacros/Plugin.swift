import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ESWMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        RenderMacro.self,
        InlineESWMacro.self,
    ]
}
