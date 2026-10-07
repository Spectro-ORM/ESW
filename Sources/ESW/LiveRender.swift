import Foundation

/// A compiled HTML template split into literal spans, escaped values and keyed lists.
public struct ESWLiveRender: Codable, Equatable, Sendable {
    /// Literal HTML spans surrounding each dynamic value.
    public let statics: [String]
    /// Rendered dynamic HTML, with escaping already applied by the compiler.
    public let dynamics: [String]
    /// Keyed comprehensions occupying dynamic slots. Their string slots are empty.
    public let keyed: [String: ESWKeyedRender]

    /// Creates a render from interleaved literal and dynamic spans.
    /// - Precondition: `statics.count == dynamics.count + 1`.
    /// - Important: Dynamic strings are inserted verbatim; escape untrusted text
    ///   before constructing a render manually.
    public init(statics: [String], dynamics: [String], keyed: [String: ESWKeyedRender] = [:]) {
        precondition(statics.count == dynamics.count + 1, "A live render needs one literal span around each dynamic value")
        precondition(Self.validKeyedSlots(keyed, dynamics: dynamics), "Invalid keyed dynamic slot")
        self.statics = statics
        self.dynamics = dynamics
        self.keyed = keyed
    }

    /// The complete HTML obtained by interleaving the spans.
    public var html: String {
        var result = statics[0]
        for (index, value) in dynamics.enumerated() { result += (keyed[String(index)]?.html ?? value) + statics[index + 1] }
        return result
    }

    /// A complete patch containing all statics and dynamic values.
    public var snapshot: ESWLivePatch {
        ESWLivePatch(statics: statics,
                     dynamics: Dictionary(uniqueKeysWithValues: dynamics.enumerated().map { (String($0.offset), $0.element) }),
                     keyed: keyed.isEmpty ? nil : keyed.mapValues(\.snapshot))
    }

    /// Returns changes needed to advance this render to `next`.
    ///
    /// Equal static arrays produce changed dynamic values and keyed row patches.
    /// A different static shape produces a full snapshot. Every template expression
    /// still evaluates during rendering; this method compares rendered output.
    public func diff(to next: ESWLiveRender) -> ESWLivePatch {
        guard statics == next.statics else { return next.snapshot }
        var changed: [String: String] = [:]
        var keyedChanges: [String: ESWKeyedPatch] = [:]
        for (index, value) in next.dynamics.enumerated() {
            let slot = String(index)
            if let nextRows = next.keyed[slot] {
                if let previousRows = keyed[slot] {
                    let patch = previousRows.diff(to: nextRows)
                    if !patch.isEmpty { keyedChanges[slot] = patch }
                } else {
                    changed[slot] = ""
                    keyedChanges[slot] = nextRows.snapshot
                }
            } else if keyed[slot] != nil || value != dynamics[index] {
                // A string update also removes any previous keyed slot.
                changed[slot] = value
            }
        }
        return ESWLivePatch(statics: nil, dynamics: changed, keyed: keyedChanges.isEmpty ? nil : keyedChanges)
    }

    private static func validKeyedSlots(_ keyed: [String: ESWKeyedRender], dynamics: [String]) -> Bool {
        keyed.keys.allSatisfy { key in
            guard let index = Int(key), String(index) == key, dynamics.indices.contains(index) else { return false }
            return dynamics[index].isEmpty
        }
    }

    /// Decodes a render, rejecting inconsistent static/dynamic counts.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statics = try container.decode([String].self, forKey: .statics)
        dynamics = try container.decode([String].self, forKey: .dynamics)
        keyed = try container.decodeIfPresent([String: ESWKeyedRender].self, forKey: .keyed) ?? [:]
        guard statics.count == dynamics.count + 1, Self.validKeyedSlots(keyed, dynamics: dynamics) else {
            throw DecodingError.dataCorruptedError(forKey: .statics, in: container, debugDescription: "Invalid live render shape")
        }
    }
}

/// `statics != nil` replaces the entire render snapshot; otherwise only the
/// listed dynamic indices change. The transport supplies revision ordering.
public struct ESWLivePatch: Codable, Equatable, Sendable {
    /// Replacement literal spans, or nil when applying an incremental patch.
    public let statics: [String]?
    /// Dynamic values keyed by their decimal, zero-based index.
    /// Missing keys in an incremental patch retain their previous values.
    public let dynamics: [String: String]
    /// Comprehension updates by dynamic slot. A string update clears that slot first.
    public let keyed: [String: ESWKeyedPatch]?

    var isEmpty: Bool { statics == nil && dynamics.isEmpty && (keyed?.isEmpty ?? true) }
}

/// Ordered row identities and their structured renders, scoped to one comprehension.
public struct ESWKeyedRender: Codable, Equatable, Sendable {
    public let order: [String]
    public let entries: [String: ESWLiveRender]

    init(order: [String], entries: [String: ESWLiveRender]) {
        self.order = order
        self.entries = entries
    }

    public var html: String { order.map { entries[$0]!.html }.joined() }

    public var snapshot: ESWKeyedPatch {
        ESWKeyedPatch(order: order, entries: entries.mapValues(\.snapshot))
    }

    public func diff(to next: ESWKeyedRender) -> ESWKeyedPatch {
        var changed: [String: ESWLivePatch] = [:]
        for key in next.order {
            let row = next.entries[key]!
            let patch = entries[key]?.diff(to: row) ?? row.snapshot
            if !patch.isEmpty { changed[key] = patch }
        }
        return ESWKeyedPatch(order: order == next.order ? nil : next.order, entries: changed)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decode([String].self, forKey: .order)
        entries = try container.decode([String: ESWLiveRender].self, forKey: .entries)
        guard Set(order).count == order.count, Set(order) == Set(entries.keys) else {
            throw DecodingError.dataCorruptedError(forKey: .order, in: container, debugDescription: "Invalid keyed row identities")
        }
    }
}

/// Changed rows and an optional replacement order. Omitted rows retain their content;
/// identities absent from a replacement order are removed.
public struct ESWKeyedPatch: Codable, Equatable, Sendable {
    public let order: [String]?
    public let entries: [String: ESWLivePatch]

    var isEmpty: Bool { order == nil && entries.isEmpty }
}

/// Collects the rows of a compiled `:for` / `:key` comprehension.
public struct ESWKeyedBuffer: Sendable {
    private var order: [String] = []
    private var entries: [String: ESWLiveRender] = [:]
    private var renders: [ESWLiveRender] = []
    private var validKeys = true

    public init() {}

    /// Keys must have stable, unique JSON encodings within the comprehension.
    /// Duplicate or unencodable keys fall back to a complete HTML fragment.
    public mutating func append<Key: Encodable>(key: Key, _ body: (inout ESWLiveBuffer) -> Void) {
        var buffer = ESWLiveBuffer()
        body(&buffer)
        let row = buffer.finalize()
        renders.append(row)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(key), let identity = String(data: data, encoding: .utf8),
              entries[identity] == nil else {
            validKeys = false
            return
        }
        order.append(identity)
        entries[identity] = row
    }

    fileprivate var render: ESWKeyedRender? {
        validKeys ? ESWKeyedRender(order: order, entries: entries) : nil
    }
    fileprivate var html: String { renders.map(\.html).joined() }
}

/// Compiler output uses the same append operations as the String renderer.
public struct ESWLiveBuffer: Sendable {
    private var statics = [""]
    private var dynamics: [String] = []
    private var keyed: [String: ESWKeyedRender] = [:]

    /// Creates a buffer with one empty literal span.
    public init() {}
    /// Extends the current literal span without introducing a dynamic slot.
    public mutating func append(_ text: String) { statics[statics.count - 1] += text }
    /// Escapes a value for HTML body output and appends it as a dynamic slot.
    public mutating func appendEscaped<T>(_ value: T) { appendUnsafe(ESW.escape(value)) }
    /// Escapes text without boxing it. Same output as the generic overload.
    public mutating func appendEscaped(_ value: String) { appendUnsafe(ESW.escaped(value)) }
    /// Escapes optional text without boxing it; `nil` produces an empty slot.
    public mutating func appendEscaped(_ value: String?) { appendUnsafe(value.map(ESW.escaped) ?? "") }
    /// Appends an integer slot, which never needs escaping.
    public mutating func appendEscaped(_ value: Int) { appendUnsafe(String(value)) }
    /// Appends a raw dynamic slot; the caller owns its escaping and trust decision.
    public mutating func appendUnsafe(_ html: String) {
        dynamics.append(html)
        statics.append("")
    }
    /// Returns a snapshot without clearing the buffer.
    public func finalize() -> ESWLiveRender { ESWLiveRender(statics: statics, dynamics: dynamics, keyed: keyed) }

    /// Appends one stable dynamic slot containing independently diffable keyed rows.
    public mutating func appendKeyed(_ body: (inout ESWKeyedBuffer) -> Void) {
        var rows = ESWKeyedBuffer()
        body(&rows)
        if let render = rows.render {
            keyed[String(dynamics.count)] = render
            appendUnsafe("")
        } else {
            appendUnsafe(rows.html)
        }
    }
}
