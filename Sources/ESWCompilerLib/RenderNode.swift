/// An ordinary token or a resolved component subtree consumed by the generator.
public indirect enum RenderNode: Equatable, Sendable {
    case token(Token)
    case component(ComponentNode)
}

/// One parsed named slot entry, before it becomes string or typed deferred content.
public struct Slot: Equatable, Sendable {
    public let name: String
    public let nodes: [RenderNode]
    public let attributes: [ComponentAttribute]
    public let metadata: Metadata

    public init(name: String, nodes: [RenderNode], attributes: [ComponentAttribute] = [],
                metadata: Metadata = Metadata(file: "<inline>", line: 1, column: 1)) {
        self.name = name
        self.nodes = nodes
        self.attributes = attributes
        self.metadata = metadata
    }
}

/// A component call with attributes, named entries, and optional default content.
public struct ComponentNode: Equatable, Sendable {
    public let name: String
    public let attributes: [ComponentAttribute]
    /// Named slot content, keyed by slot name. Ordered pairs — not a Dictionary.
    /// Order preserved from source; codegen sorts alphabetically at emit time.
    public let namedSlots: [Slot]
    /// Bare content outside any named slot → emitted as `content:` argument.
    /// Empty array means no `content:` argument is emitted.
    public let defaultSlot: [RenderNode]
    public let metadata: Metadata
}
