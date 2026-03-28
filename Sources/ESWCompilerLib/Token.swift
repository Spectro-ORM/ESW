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

public enum Token: Equatable, Sendable {
    case text(String, metadata: Metadata)
    case output(String, metadata: Metadata)
    case rawOutput(String, metadata: Metadata)
    case code(String, metadata: Metadata)
    case comment(String, metadata: Metadata)
    case assigns(String, metadata: Metadata)
}
