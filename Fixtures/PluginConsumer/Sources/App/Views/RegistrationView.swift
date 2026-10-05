import ESW
import Foundation

@ESWTemplate("registration.esw")
struct RegistrationView {
    let email: String
    let csrfToken: String
    let error: String?

    var title: String { "Register" }
    func normalize(_ value: String) -> String { value.uppercased() }
}
