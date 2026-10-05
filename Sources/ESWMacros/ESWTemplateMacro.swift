import ESWCompilerLib
import SwiftSyntax
import SwiftSyntaxMacros

/// Declares the view conformance; ESWBuildPlugin generates the rendering method
/// from tracked inputs. Macro expansion never opens a template file.
public struct ESWTemplateMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        _ = try TemplateView.discover(source: declaration.trimmedDescription, sourceFile: "@ESWTemplate")
        return [try ExtensionDeclSyntax("extension \(type): ESWView {}")]
    }
}
