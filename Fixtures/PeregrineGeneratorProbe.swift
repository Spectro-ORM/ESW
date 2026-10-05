import Foundation

/// Compiled with Roost's generator sources by scripts/check_integration.py.
@main
struct RoostGeneratorProbe {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        func write(_ path: String, _ content: String) throws {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        let fields = try FieldParser.parse(["title:string", "count:int"])
        let routes = GeneratorTemplates.htmlRoutes(name: "UserProfile", pluralName: "UserProfiles", fields: fields)
        precondition(routes.contains("conn.render(UserProfilesIndexView(userProfiles: userProfiles)"))
        precondition(routes.contains("UserProfileNewView()"))
        precondition(routes.contains("UserProfileEditView(userProfile: userProfile)"))
        precondition(!routes.contains("csrfToken"))
        try write("Routes/UserProfileRoutes.swift", routes)
        let pages = [
            ("index", GeneratorTemplates.listTemplate(name: "UserProfile", fields: fields)),
            ("show", GeneratorTemplates.showTemplate(name: "UserProfile", fields: fields)),
            ("new", GeneratorTemplates.newTemplate(name: "UserProfile", fields: fields)),
            ("edit", GeneratorTemplates.editTemplate(name: "UserProfile", fields: fields)),
        ]
        for (page, template) in pages {
            precondition(!template.contains("<%!"))
            try write("Views/user_profiles/\(page).esw", template)
        }
        let authRoutes = AuthTemplates.authRoutes()
        precondition(authRoutes.contains("conn.render(RegisterView()"))
        precondition(authRoutes.contains("conn.render(LoginView("))
        precondition(!authRoutes.contains("csrfToken"))
        for (file, source) in GeneratorTemplates.htmlViews(name: "UserProfile", fields: fields) {
            try write("Views/user_profiles/\(file)", source)
        }
        try write("Views/auth/LoginView.swift", AuthTemplates.view(name: "LoginView", template: "login.esw"))
        try write("Views/auth/RegisterView.swift", AuthTemplates.view(name: "RegisterView", template: "register.esw"))
        try write("Views/LayoutView.swift", ProjectTemplates.layoutView)
        try write("Routes/AuthRoutes.swift", authRoutes)
        try write("Views/auth/login.esw", AuthTemplates.loginTemplate())
        try write("Views/auth/register.esw", AuthTemplates.registerTemplate())
        try write("Views/layout.esw", ProjectTemplates.layoutESW(appName: "Probe"))
        precondition(ProjectTemplates.tailwindConfig(appName: "Probe").contains("*.{esw,heex}"))
        for includeESW in [true, false] {
            try write("manifest-\(includeESW)/Package.swift", ProjectTemplates.packageSwift(appName: "Probe", includeDB: false, includeESW: includeESW))
        }
        print("Roost generator contracts passed.")
    }
}
