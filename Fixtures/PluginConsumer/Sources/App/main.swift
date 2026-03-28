import ESW
import Nexus

// --- Partial: buffer function exists and is callable ---

let greeting = _renderGreetingBuffer(name: "World")
assert(greeting.contains("Hello"), "Default greeting should be Hello")
assert(greeting.contains("World"), "Name should appear in output")

// --- Default parameter works ---

let custom = _renderGreetingBuffer(name: "Swift", greeting: "Howdy")
assert(custom.contains("Howdy"), "Custom greeting should appear")
assert(custom.contains("Swift"), "Name should appear in custom output")

// --- HTML escaping works ---

let xss = _renderGreetingBuffer(name: "<script>alert('xss')</script>")
assert(!xss.contains("<script>"), "Script tags must be escaped")
assert(xss.contains("&lt;script&gt;"), "Script tags must be HTML-escaped")

// --- Non-partial: conn function exists ---

let conn = Connection()
let helloResult = renderHello(conn: conn)
assert(helloResult.body.contains("Hello, World!"), "hello.esw should render")

// --- Layout with raw content ---

let layoutResult = renderLayout(conn: conn, title: "Test", content: "<p>Body</p>")
assert(layoutResult.body.contains("<title>Test</title>"), "Title should be escaped")
assert(layoutResult.body.contains("<p>Body</p>"), "Raw content should not be escaped")

// --- Partial via conn function ---

let greetConn = renderGreeting(conn: conn, name: "Tester")
assert(greetConn.body.contains("Hello"), "Conn variant should work")
assert(greetConn.body.contains("Tester"), "Conn variant should pass name")

// --- Index page: default (no items) ---

let indexDefault = renderIndex(conn: conn)
assert(indexDefault.body.contains("<title>Welcome</title>"), "Default title should be Welcome")
assert(indexDefault.body.contains("<h1>Welcome</h1>"), "H1 should show title")
assert(indexDefault.body.contains("No items yet."), "Empty items should show placeholder")
assert(!indexDefault.body.contains("<ul>"), "No list when items are empty")

// --- Index page: with items ---

let indexWithItems = renderIndex(conn: conn, title: "Stuff", items: ["Alpha", "Beta"])
assert(indexWithItems.body.contains("<title>Stuff</title>"), "Custom title should appear")
assert(indexWithItems.body.contains("<li>Alpha</li>"), "First item should render")
assert(indexWithItems.body.contains("<li>Beta</li>"), "Second item should render")
assert(!indexWithItems.body.contains("No items yet."), "Placeholder hidden when items exist")

// --- Index page: HTML escaping in items ---

let indexXSS = renderIndex(conn: conn, items: ["<img onerror=alert(1)>"])
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

print("All fixture assertions passed.")
