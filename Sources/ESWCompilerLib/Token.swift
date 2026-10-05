/// A template source location attached to tokens and render nodes.
public struct Metadata: Equatable, Sendable {
    /// The original filename or diagnostic label.
    public let file: String
    /// The one-based line number.
    public let line: Int
    /// The one-based column number.
    public let column: Int

    /// Creates a source location without validating the supplied coordinates.
    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

/// A component or slot argument before Swift code generation.
public struct ComponentAttribute: Equatable, Sendable {
    /// The argument label or template directive name.
    public let key: String
    /// `nil` for boolean (bare) attributes; non-nil for `attr="string"` or `attr={expr}`.
    public let value: ComponentAttributeValue?

    /// Creates an argument; a nil value represents a bare boolean attribute.
    public init(key: String, value: ComponentAttributeValue?) {
        self.key = key
        self.value = value
    }
}

/// The source form of a component or slot attribute value.
public enum ComponentAttributeValue: Equatable, Sendable {
    case string(String)      // attr="literal"
    case expression(String)  // attr={swiftExpr}
}

/// A lexical template item with its original source location.
/// Components and slots are paired into a tree by ``ComponentResolver``.
public enum Token: Equatable, Sendable {
    case text(String, metadata: Metadata)
    case output(String, metadata: Metadata)
    case rawOutput(String, metadata: Metadata)
    case code(String, metadata: Metadata)
    case comment(String, metadata: Metadata)
    case assigns(String, metadata: Metadata)
    case htmlAttribute(name: String, expression: String, metadata: Metadata)
    case htmlAttributes(expression: String, metadata: Metadata)
    /// A keyed HTML comprehension; its body ends at `keyedClose`.
    case keyedOpen(loop: String, key: String, condition: String?, metadata: Metadata)
    case keyedClose(conditional: Bool, metadata: Metadata)
    /// A `<.tag-name attr="val" attr2={expr} />` or `<.tag-name>...</.tag-name>` component tag.
    case componentTag(
        name: String,
        attributes: [ComponentAttribute],
        selfClosing: Bool,
        metadata: Metadata
    )
    case componentClose(name: String, metadata: Metadata)
    /// A `<:name>` slot opening tag.
    case slotOpen(name: String, attributes: [ComponentAttribute] = [], selfClosing: Bool = false, metadata: Metadata)
    /// A `</:name>` slot closing tag.
    case slotClose(name: String, metadata: Metadata)
}
