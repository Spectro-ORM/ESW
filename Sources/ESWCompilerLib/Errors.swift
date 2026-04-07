public enum ESWTokenizerError: Error, Equatable {
    case unterminatedTag(file: String, line: Int, column: Int)
    case malformedComponentTag(file: String, line: Int, column: Int)
}

public enum ESWAssignsError: Error, Equatable {
    case assignsNotFirst(file: String, line: Int)
    case invalidDeclaration(file: String, line: Int, text: String)
}

public enum ESWComponentError: Error, Equatable {
    case unterminatedComponent(file: String, line: Int, column: Int)
    case unmatchedComponentClose(file: String, line: Int, column: Int)
    case unterminatedSlot(file: String, line: Int, column: Int)
    case unmatchedSlotClose(file: String, line: Int, column: Int)
    case duplicateSlot(name: String, file: String, line: Int)
    case slotOutsideComponent(file: String, line: Int, column: Int)
}
