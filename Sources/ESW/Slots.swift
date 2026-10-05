/// A typed slot entry. Attributes are evaluated by the caller; the body is
/// evaluated only when the component renders it with an input value.
public struct ESWSlot<Attributes, Input> {
    /// Values supplied when the caller creates this entry.
    public let attributes: Attributes
    private let body: (Input) -> String

    /// Creates an entry whose body is evaluated on each call to ``render(_:)``.
    /// The body must escape dynamic text in the HTML it returns.
    public init(attributes: Attributes, render: @escaping (Input) -> String) {
        self.attributes = attributes
        self.body = render
    }

    /// Renders this entry with a value supplied by its component.
    public func render(_ input: Input) -> String { body(input) }
}

/// The attribute type for a typed slot entry with no named attributes.
public struct ESWEmptySlotAttributes: Sendable {
    /// Creates an empty attribute value.
    public init() {}
}

/// Keeps slot entries separate and in source order, including entries created
/// by conditional branches or loops in a template.
@resultBuilder
public enum ESWSlotBuilder<Attributes, Input> {
    public typealias Entry = ESWSlot<Attributes, Input>
    public static func buildExpression(_ entry: Entry) -> [Entry] { [entry] }
    public static func buildBlock(_ entries: [Entry]...) -> [Entry] { entries.flatMap { $0 } }
    public static func buildOptional(_ entries: [Entry]?) -> [Entry] { entries ?? [] }
    public static func buildEither(first entries: [Entry]) -> [Entry] { entries }
    public static func buildEither(second entries: [Entry]) -> [Entry] { entries }
    public static func buildArray(_ entries: [[Entry]]) -> [Entry] { entries.flatMap { $0 } }
    public static func buildLimitedAvailability(_ entries: [Entry]) -> [Entry] { entries }
}

extension ESW {
    /// Assembles typed entries while preserving order across branches and loops.
    ///
    /// This evaluates the builder, not the deferred bodies in each ``ESWSlot``.
    public static func slots<Attributes, Input>(
        @ESWSlotBuilder<Attributes, Input> _ content: () -> [ESWSlot<Attributes, Input>]
    ) -> [ESWSlot<Attributes, Input>] {
        content()
    }
}

/// Slot bodies already escape dynamic text. The result can be embedded with
/// `{renderSlot(entry, value)}` without escaping its HTML a second time.
public func renderSlot<Attributes, Input>(_ slot: ESWSlot<Attributes, Input>, _ input: Input) -> ESWValue {
    .safe(slot.render(input))
}

/// Renders entries in order with the same input, marking their combined HTML as trusted.
public func renderSlot<Attributes, Input>(_ slots: [ESWSlot<Attributes, Input>], _ input: Input) -> ESWValue {
    .safe(slots.map { $0.render(input) }.joined())
}

/// Renders a slot that needs no input and marks its HTML as trusted.
public func renderSlot<Attributes>(_ slot: ESWSlot<Attributes, Void>) -> ESWValue {
    renderSlot(slot, ())
}

/// Renders input-free entries in order and marks their combined HTML as trusted.
public func renderSlot<Attributes>(_ slots: [ESWSlot<Attributes, Void>]) -> ESWValue {
    renderSlot(slots, ())
}
