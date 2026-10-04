import ESW

struct Person { let name: String }
struct PersonColumn { let label: String }

struct PersonTable: ESWComponent {
    static func render(people: [Person], column: [ESWSlot<PersonColumn, Person>]) -> String {
        let header = column.map { "<th>\(ESW.escape($0.attributes.label))</th>" }.joined()
        let rows = people.map { person in
            "<tr>" + column.map { "<td>\($0.render(person))</td>" }.joined() + "</tr>"
        }.joined()
        return "<table><thead>\(header)</thead><tbody>\(rows)</tbody></table>"
    }
}
