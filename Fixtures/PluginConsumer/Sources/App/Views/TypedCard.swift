import ESW
@ESWTemplate("typed-card.hesw")
public struct TypedCard<Value: CustomStringConvertible> {
    let value: Value
    var show = true
}
