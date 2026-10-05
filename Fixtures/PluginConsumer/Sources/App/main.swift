import ESW
import Nexus

// --- Partial: buffer function exists and is callable ---

let renderedGreeting = _renderGreetingBuffer(name: "World")
assert(renderedGreeting.contains("Hello"), "Default greeting should be Hello")
assert(renderedGreeting.contains("World"), "Name should appear in output")

// --- Default parameter works ---

let custom = _renderGreetingBuffer(name: "Swift", greeting: "Howdy")
assert(custom.contains("Howdy"), "Custom greeting should appear")
assert(custom.contains("Swift"), "Name should appear in custom output")

// --- HTML escaping works ---

let xss = _renderGreetingBuffer(name: "<script>alert('xss')</script>")
assert(!xss.contains("<script>"), "Script tags must be escaped")
assert(xss.contains("&lt;script&gt;"), "Script tags must be HTML-escaped")

// --- Non-partial: String-returning function wrapped in conn.html() ---

let conn = Connection()
let helloResult = conn.html(renderHello())
assert(helloResult.body.contains("Hello, World!"), "hello.esw should render")

// --- Layout with raw content ---

let layoutResult = conn.html(renderLayout(title: "Test", content: "<p>Body</p>"))
assert(layoutResult.body.contains("<title>Test</title>"), "Title should be in head")
assert(layoutResult.body.contains("<p>Body</p>"), "Raw content should not be escaped")

// --- Index page: default (no items) ---

let indexDefault = conn.html(renderIndex())
assert(indexDefault.body.contains("<title>Welcome</title>"), "Default title should be Welcome")
assert(indexDefault.body.contains("<h1>Welcome</h1>"), "H1 should show title")
assert(indexDefault.body.contains("No items yet."), "Empty items should show placeholder")
assert(!indexDefault.body.contains("<ul>"), "No list when items are empty")

// --- Index page: with items ---

let indexWithItems = conn.html(renderIndex(title: "Stuff", items: ["Alpha", "Beta"]))
assert(indexWithItems.body.contains("<title>Stuff</title>"), "Custom title should appear")
assert(indexWithItems.body.contains("<li>Alpha</li>"), "First item should render")
assert(indexWithItems.body.contains("<li>Beta</li>"), "Second item should render")
assert(!indexWithItems.body.contains("No items yet."), "Placeholder hidden when items exist")

// --- Index page: HTML escaping in items ---

let indexXSS = conn.html(renderIndex(items: ["<img onerror=alert(1)>"]))
assert(!indexXSS.body.contains("<img onerror"), "Item content must be escaped")
assert(indexXSS.body.contains("&lt;img onerror"), "Angle brackets must be entities")

// --- render() helper: embed partials via <%= %> without double-escaping ---

let rendered = ESW.escape(render(_renderGreetingBuffer(name: "World")))
assert(rendered.contains("Hello"), "render() should pass through safe content")
assert(rendered.contains("World"), "render() should preserve partial output")
assert(!rendered.contains("&lt;p&gt;"), "render() should NOT double-escape HTML tags from partial")

// --- Layout convenience helper ---

let layoutConn = conn.html(title: "Convenience", layout: renderLayout) {
    _renderGreetingBuffer(name: "World")
}
assert(layoutConn.body.contains("<title>Convenience</title>"), "Layout helper should pass title")
assert(layoutConn.body.contains("Hello"), "Layout helper should render content block")
assert(layoutConn.body.contains("World"), "Layout helper content should include partial output")

// --- Asset path helper ---

let manifest = AssetManifest(entries: ["app.css": "app-abc123.css", "app.js": "app-def456.js"])
func assetPath(_ name: String) -> String { manifest.path(for: name) }

let headHTML = _renderHeadBuffer(title: "Assets")
assert(headHTML.contains("app-abc123.css"), "assetPath should resolve to fingerprinted filename")
assert(headHTML.contains("<title>Assets</title>"), "Head partial should include title")
assert(!headHTML.contains("\"app.css\""), "Original filename should be replaced by manifest lookup")

// HTML-aware templates compile through the same build plugin.
let tasks = renderTasks(items: ["<swift>"], counts: ["<swift>": 2])
assert(tasks.contains("<li data-count=\"2\">&lt;swift&gt;</li>"))
assert(!renderTasks(items: [], show: false).contains("<section"))
assert(renderTasks(items: []).contains("class=\"tasks empty\""))
assert(renderGreeting(name: "World") == _renderGreetingBuffer(name: "World"))

// File macros and build-plugin functions use the same compiler pipeline.
let name = "<Macro>"
let greeting = "Hello"
assert(#render("_greeting.esw") == _renderGreetingBuffer(name: name))
let items = ["<swift>"]
let counts = ["<swift>": 2]
let show = true
assert(#render("tasks.heex") == tasks)
let usersPage = renderUsersIndex(users: ["<Ada>"])
assert(usersPage.contains("<h1>User directory</h1><time>0</time><p>&lt;Ada&gt;</p>"))
assert(renderPostsIndex(posts: ["<post>"]).contains("<li>&lt;post&gt;</li>"))
let table = renderUsersTable(people: [Person(name: "<Ada>")], showDetails: false)
assert(table.contains("<th>Name</th>"))
assert(!table.contains("Details"))
assert(table.contains("<td><b>&lt;Ada&gt;</b></td>"))
let liveCounter = renderCounterLive(count: 1)
assert(liveCounter.html.contains("<output>1</output>"))
assert(liveCounter.diff(to: renderCounterLive(count: 2)).dynamics == ["0": "2"])
if let marker = CommandLine.arguments.dropFirst().first, marker != "--typed-template", marker != "--keyed-wire" {
    assert(renderPostsIndex(posts: []).contains(marker), "A template-only edit must update the compiled renderer")
}
let registration = RegistrationView(email: "<Ada>", csrfToken: "\"token", error: "<Oops>").render()
assert(registration.contains("<h1>Register</h1>"))
assert(registration.contains("<p role=\"alert\">&lt;Oops&gt;</p>"))
assert(registration.contains("value=\"&lt;Ada&gt;\""))
assert(registration.contains("value=\"&quot;token\""))
assert(registration.contains("<p>&lt;ADA&gt;</p>"))
assert(registration.contains("<time>0</time>"), "Companion imports must be available in generated methods")
assert(!RegistrationView(email: "", csrfToken: "", error: nil).render().contains("role=\"alert\""))
assert(TypedCard(value: 42).render().contains("<p>42</p>"))
assert(!TypedCard(value: "<hidden>", show: false).render().contains("<article"))
assert(TypedCounter(count: 1).render().diff(to: TypedCounter(count: 2).render()).dynamics == ["0": "2"])
if CommandLine.arguments.dropFirst().first == "--typed-template",
   let marker = CommandLine.arguments.dropFirst(2).first {
    assert(registration.contains(marker), "A typed template-only edit must update render()")
}
print("All ESW, HEEx, macro, namespaced template, typed view, and typed slot fixture assertions passed.")
if CommandLine.arguments.dropFirst().first == "--keyed-wire" {
    print("KEYED_WIRE:" + (try keyedWireFixture()))
}
