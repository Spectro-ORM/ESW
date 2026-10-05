/// Lexical failures involving an incomplete tag or malformed component syntax.
public enum ESWTokenizerError: Error, Equatable {
    case unterminatedTag(file: String, line: Int, column: Int)
    case malformedComponentTag(file: String, line: Int, column: Int)
}

/// Errors in the position or contents of a template declaration block.
public enum ESWAssignsError: Error, Equatable {
    case assignsNotFirst(file: String, line: Int)
    case invalidDeclaration(file: String, line: Int, text: String)
}

/// Component and slot nesting errors detected while resolving the render tree.
public enum ESWComponentError: Error, Equatable {
    case unterminatedComponent(file: String, line: Int, column: Int)
    case unmatchedComponentClose(file: String, line: Int, column: Int)
    case unterminatedSlot(file: String, line: Int, column: Int)
    case unmatchedSlotClose(file: String, line: Int, column: Int)
    case duplicateSlot(name: String, file: String, line: Int)
    case slotOutsideComponent(file: String, line: Int, column: Int)
}

extension ESWTokenizerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unterminatedTag(let file, let line, let column):
            return "\(file):\(line):\(column): error: unterminated ESW tag"
        case .malformedComponentTag(let file, let line, let column):
            return "\(file):\(line):\(column): error: malformed component or slot tag"
        }
    }
}

extension ESWAssignsError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .assignsNotFirst(let file, let line):
            return "\(file):\(line): error: assigns block must precede template content"
        case .invalidDeclaration(let file, let line, let text):
            return "\(file):\(line): error: invalid declaration: \(text)"
        }
    }
}

extension ESWComponentError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unterminatedComponent(let file, let line, let column):
            return "\(file):\(line):\(column): error: unterminated component tag"
        case .unmatchedComponentClose(let file, let line, let column):
            return "\(file):\(line):\(column): error: unmatched component closing tag"
        case .unterminatedSlot(let file, let line, let column):
            return "\(file):\(line):\(column): error: unterminated slot tag"
        case .unmatchedSlotClose(let file, let line, let column):
            return "\(file):\(line):\(column): error: unmatched slot closing tag"
        case .duplicateSlot(let name, let file, let line):
            return "\(file):\(line): error: duplicate slot '\(name)'"
        case .slotOutsideComponent(let file, let line, let column):
            return "\(file):\(line):\(column): error: slot must belong to a component"
        }
    }
}
