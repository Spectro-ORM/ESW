/// Conforming types can be rendered as a component inside `.esw` templates
/// using the `<.tag-name attr="..." />` syntax.
///
/// The tag name maps to the type name via kebab-to-PascalCase conversion:
/// `<.button>` → `Button`, `<.user-card>` → `UserCard`.
///
/// ```swift
/// struct Button: ESWComponent {
///     static func render(label: String, disabled: Bool = false) -> String {
///         "<button\(disabled ? " disabled" : "")>\(ESW.escape(label))</button>"
///     }
/// }
/// ```
///
/// In a template:
/// ```
/// <.button label="Click me" />
/// <.button label={item.name} disabled />
/// <.card title="Hello">
///   <:header>Welcome</:header>
///   <p>Body content</p>
/// </.card>
/// ```
///
/// ## Argument Ordering Convention
///
/// When using content slots, component `render()` functions should follow this argument order:
/// 1. Attributes (in source order from the template)
/// 2. Named slots (alphabetically by slot name)
/// 3. Default content slot (always last, with default value for optional content)
///
/// ```swift
/// struct Card: ESWComponent {
///     static func render(
///         title: String,              // attribute (source order)
///         header: String,             // named slot (alphabetical)
///         footer: String = "",        // named slot (alphabetical, optional)
///         content: String = ""        // default slot (always last, optional)
///     ) -> String { ... }
/// }
/// ```
public protocol ESWComponent {
    /// Renders the component to an HTML string.
    /// The compiler calls the concrete type's `render(...)` method directly,
    /// so the signature is determined by the implementing type's static method —
    /// this protocol does not mandate a specific parameter list.
    static func render() -> String
}
