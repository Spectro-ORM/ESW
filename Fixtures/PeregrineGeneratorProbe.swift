import Foundation

/// Compiled with Peregrine's generator sources by scripts/check_integration.py.
@main
struct PeregrineGeneratorProbe {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        func write(_ path: String, _ content: String) throws {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        let fields = try FieldParser.parse(["title:string", "count:int"])
        let routes = GeneratorTemplates.htmlRoutes(name: "UserProfile", pluralName: "UserProfiles", fields: fields)
        precondition(routes.contains("conn.html("))
        precondition(routes.contains("renderUserProfilesIndex(conn: conn, userProfiles: userProfiles)"))
        precondition(routes.contains("renderUserProfilesNew(conn: conn, csrfToken:"))
        precondition(routes.contains("renderUserProfilesEdit(conn: conn, userProfile: userProfile, csrfToken:"))
        precondition(!routes.contains("conn.render("))
        try write("Routes/UserProfileRoutes.swift", routes)
        let pages = [
            ("index", GeneratorTemplates.listTemplate(name: "UserProfile", fields: fields)),
            ("show", GeneratorTemplates.showTemplate(name: "UserProfile", fields: fields)),
            ("new", GeneratorTemplates.newTemplate(name: "UserProfile", fields: fields)),
            ("edit", GeneratorTemplates.editTemplate(name: "UserProfile", fields: fields)),
        ]
        for (page, template) in pages {
            precondition(template.contains("import Peregrine"))
            try write("Views/user_profiles/\(page).esw", template)
        }
        let authRoutes = AuthTemplates.authRoutes()
        precondition(authRoutes.contains("conn.html("))
        precondition(authRoutes.contains("renderAuthRegister("))
        precondition(authRoutes.contains("renderAuthLogin("))
        precondition(!authRoutes.contains("conn.render("))
        try write("Routes/AuthRoutes.swift", authRoutes)
        try write("Views/auth/login.esw", AuthTemplates.loginTemplate())
        try write("Views/auth/register.esw", AuthTemplates.registerTemplate())
        try write("Views/layout.esw", ProjectTemplates.layoutESW(appName: "Probe"))
        precondition(ProjectTemplates.tailwindConfig(appName: "Probe").contains("*.{esw,heex}"))
        for includeESW in [true, false] {
            try write("manifest-\(includeESW)/Package.swift", ProjectTemplates.packageSwift(appName: "Probe", includeDB: false, includeESW: includeESW))
        }
        print("Peregrine generator contracts passed.")
    }
}
