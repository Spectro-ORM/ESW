import ESW
@ESWTemplate("typed-card.heex")
public struct TypedCard<Value: CustomStringConvertible> {
    let value: Value
    var show = true
}
