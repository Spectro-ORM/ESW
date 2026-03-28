# Spec: Tokenizer & Code Generator Hardening

**Status:** Proposed
**Date:** 2026-03-27
**Depends on:** ESW core (complete)

---

## 1. Goal

Identify and cover edge cases in the tokenizer and code generator that the
initial implementation does not exercise. Fix any bugs discovered. The result is
a battle-tested compiler that handles malformed input gracefully and produces
correct output for all valid input.

---

## 2. Tokenizer Edge Cases

### 2.1 Raw string hash collisions

The code generator emits text tokens as `#"..."#`. If the text itself contains
`"#`, the raw string literal will terminate early.

**Input:**
```html
<p>Use "#" for markdown headers</p>
```

**Current output (broken):**
```swift
_buf += #"<p>Use "#" for markdown headers</p>"#
//                  ^ closes the raw string prematurely
```

**Fix:** Detect if the text contains `"#` and escalate to `##"..."##` (or
higher). The generator must find the minimum number of `#` symbols needed to
avoid collisions.

**Algorithm:**
```
func rawStringLiteral(_ s: String) -> String {
    var hashes = 1
    while s.contains(String(repeating: "#", count: hashes) + "\"") ||
          s.contains("\"" + String(repeating: "#", count: hashes)) {
        hashes += 1
    }
    let h = String(repeating: "#", count: hashes)
    return "\(h)\"\(s)\"\(h)"
}
```

### 2.2 Text containing backslash sequences

Raw string literals (`#"..."#`) don't interpret `\n`, `\t`, etc., so
backslashes in HTML are safe. Verify this with tests.

### 2.3 Empty tags

```html
<%= %>     ← empty expression
<% %>      ← empty code
<%# %>     ← empty comment
<%! %>     ← empty assigns (no parameters)
```

Expected behavior:
- `<%= %>` → `ESW.escape()` — Swift compiler error (good, expected).
- `<% %>` → empty line in generated code (harmless).
- `<%# %>` → dropped (correct).
- `<%! %>` → no parameters (correct, function takes only `conn`).

### 2.4 Nested `<%` in code blocks

```html
<% let x = "<%=" %>
```

The tokenizer scans for `%>` to close the tag. The `<%=` inside a string
literal in the code block should not confuse it (it won't — the tokenizer
doesn't parse Swift, it just scans for `%>`). Verify with a test.

### 2.5 `%>` inside Swift string literals in code blocks

```html
<% let x = "%>" %>
```

This **will** break — the tokenizer finds the `%>` inside the string literal
and treats it as the closing delimiter. This is a known limitation (same as ERB).

**Mitigation:** Document this. Workaround is `%%>` inside tags.

**Test:** Verify the tokenizer produces a `.code("let x = \"")` token and a
subsequent `.text` for the rest — documenting the known behavior.

### 2.6 Multi-byte UTF-8 characters

```html
<p>Héllo 世界 🌍</p>
<%= "café" %>
```

Verify line/column tracking is correct with multi-byte characters. Columns
should count characters, not bytes.

### 2.7 Windows line endings (`\r\n`)

Templates may be edited on Windows. The tokenizer should handle `\r\n` the
same as `\n` for line counting and whitespace trimming.

### 2.8 Unterminated assigns block

```html
<%!
var x: Int
```

Should throw `unterminatedTag`. Verify.

### 2.9 Multiple assigns blocks

```html
<%!
var x: Int
%>
<%!
var y: String
%>
```

Should throw `assignsNotFirst` on the second block (it appears after other
content). Verify.

---

## 3. Code Generator Edge Cases

### 3.1 Function name collisions

Two files with names that normalize to the same function:
- `user_profile.esw` → `renderUserProfile`
- `userProfile.esw` → `renderUserprofile` (different casing)

This is a non-issue at the generator level (each file produces one function),
but it could cause Swift compiler errors at the consumer level. **Document**
the naming convention and recommend snake_case filenames.

### 3.2 Reserved Swift keywords as parameter names

```
<%!
var class: String
%>
```

Generates `class: String` in the function signature — a Swift keyword.

**Fix:** Backtick-escape parameter names that are Swift keywords:
```swift
func renderTest(conn: Connection, `class`: String) -> Connection
```

**Keyword list:** `class`, `struct`, `enum`, `protocol`, `func`, `var`, `let`,
`import`, `return`, `if`, `else`, `for`, `while`, `switch`, `case`, `default`,
`break`, `continue`, `in`, `is`, `as`, `self`, `Self`, `true`, `false`, `nil`,
`try`, `catch`, `throw`, `throws`, `guard`, `where`, `init`, `deinit`,
`extension`, `subscript`, `operator`, `typealias`, `associatedtype`, `inout`,
`static`, `public`, `private`, `internal`, `fileprivate`, `open`, `mutating`,
`nonmutating`, `override`, `convenience`, `required`, `dynamic`, `lazy`,
`final`, `weak`, `unowned`, `some`, `any`.

### 3.3 Empty text tokens after trimming

After whitespace trimming, some text tokens may become empty strings. The
generator should skip them (it currently does — verify with test).

### 3.4 Very long text segments

A 100KB block of static HTML should not cause issues with raw string literals
or buffer allocation. Test with a large input.

### 3.5 Text containing newlines in raw string output

Multi-line raw strings are fine in Swift (`#"line1\nline2"#` preserves the
literal `\n` characters). But the generated code should use actual newlines
inside the raw string, not escaped `\n`. Verify the generator handles text
tokens with embedded newlines correctly.

---

## 4. Tasks

| # | Task | Type |
|---|------|------|
| 1 | Implement raw string hash escalation in `CodeGenerator` | fix |
| 2 | Add tests for `"#` in text content | test |
| 3 | Add tests for backslash sequences in text | test |
| 4 | Add tests for empty tags | test |
| 5 | Add tests for nested `<%` in code blocks | test |
| 6 | Document `%>` in Swift string literals as known limitation | doc |
| 7 | Add UTF-8 multi-byte character tests | test |
| 8 | Add `\r\n` line ending tests | test |
| 9 | Add unterminated assigns test | test |
| 10 | Add multiple assigns blocks test | test |
| 11 | Implement keyword backtick-escaping in `AssignsParser` / `CodeGenerator` | fix |
| 12 | Add reserved keyword parameter tests | test |
| 13 | Add large input stress test | test |
| 14 | Add multi-line text in raw string test | test |

---

## 5. Verification

- `swift test` passes all new tests.
- No regressions in existing 86 tests.
- Edge case behaviors are documented in test names and comments.
