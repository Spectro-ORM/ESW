import Testing
@testable import ESWCompilerLib

@Test func tokenMetadataEquality() {
    let a = Metadata(file: "test.esw", line: 1, column: 1)
    let b = Metadata(file: "test.esw", line: 1, column: 1)
    #expect(a == b)
}

@Test func tokenEquality() {
    let m = Metadata(file: "test.esw", line: 1, column: 1)
    let a = Token.text("hello", metadata: m)
    let b = Token.text("hello", metadata: m)
    #expect(a == b)
}
