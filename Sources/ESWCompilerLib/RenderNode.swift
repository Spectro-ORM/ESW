import Algorithms

public indirect enum RenderNode: Equatable, Sendable {
    case token(Token)
    case component(ComponentNode)
}

public struct Slot: Equatable, Sendable {
    public let name: String
    public let nodes: [RenderNode]

    public init(name: String, nodes: [RenderNode]) {
        self.name = name
        self.nodes = nodes
    }
}

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