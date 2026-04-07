public struct Metadata: Equatable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct ComponentAttribute: Equatable, Sendable {
    public let key: String
    /// `nil` for boolean (bare) attributes; non-nil for `attr="string"` or `attr={expr}`.
    public let value: ComponentAttributeValue?

    public init(key: String, value: ComponentAttributeValue?) {
        self.key = key
        self.value = value
    }
}

public enum ComponentAttributeValue: Equatable, Sendable {
    case string(String)      // attr="literal"
    case expression(String)  // attr={swiftExpr}
}

public enum Token: Equatable, Sendable {
    case text(String, metadata: Metadata)
    case output(String, metadata: Metadata)
    case rawOutput(String, metadata: Metadata)
    case code(String, metadata: Metadata)
    case comment(String, metadata: Metadata)
    case assigns(String, metadata: Metadata)
    /// A `<.tag-name attr="val" attr2={expr} />` or `<.tag-name>...</.tag-name>` component tag.
    case componentTag(
        name: String,
        attributes: [ComponentAttribute],
        selfClosing: Bool,
        metadata: Metadata
    )
    case componentClose(name: String, metadata: Metadata)
    /// A `<:name>` slot opening tag.
    case slotOpen(name: String, metadata: Metadata)
    /// A `</:name>` slot closing tag.
    case slotClose(name: String, metadata: Metadata)
}
