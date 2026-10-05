/// A string with an explicit trust decision for insertion into an HTML body.
///
/// ``ESW/escape(_:)`` passes `.safe` values through and escapes `.unsafe` values.
/// Neither case makes a value safe for JavaScript, CSS, or URL contexts.
public enum ESWValue: Sendable {
    /// HTML that the caller has already escaped or intentionally trusts.
    case safe(String)
    /// Text that must be HTML-escaped before insertion.
    case unsafe(String)
}
