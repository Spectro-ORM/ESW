public enum ESWTokenizerError: Error, Equatable {
    case unterminatedTag(file: String, line: Int, column: Int)
}

public enum ESWAssignsError: Error, Equatable {
    case assignsNotFirst(file: String, line: Int)
    case invalidDeclaration(file: String, line: Int, text: String)
}
