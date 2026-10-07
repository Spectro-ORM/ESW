#!/usr/bin/env python3
"""Compile real consumers, reject invalid slot types, and verify incremental builds.

Usage: python3 scripts/check_integration.py [--roost /path/to/Roost]
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run(arguments, *, cwd=ROOT, succeeds=True):
    result = subprocess.run([str(arg) for arg in arguments], cwd=cwd, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if succeeds and result.returncode != 0:
        raise RuntimeError(output[-12000:])
    if not succeeds and result.returncode == 0:
        raise AssertionError(f"Expected failure: {arguments}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roost", "--peregrine", dest="roost", type=Path)
    options = parser.parse_args()
    run(["swift", "build", "--product", "ESWCompilerCLI"])
    run(["swift", "build", "--target", "ESW"])  # Probes import ESW and load ESWMacros.
    binary_dir = Path(run(["swift", "build", "--show-bin-path"]).strip())
    # The native build system keeps .swiftmodule files in Modules/.
    includes = [arg for path in (binary_dir, binary_dir / "Modules") if path.exists() for arg in ("-I", path)]
    # The native build system names the macro executable ESWMacros-tool.
    macros = next(path for path in (binary_dir / "ESWMacros", binary_dir / "ESWMacros-tool") if path.exists())
    plugin = ["-load-plugin-executable", f"{macros}#ESWMacros"]
    compiler = binary_dir / "ESWCompilerCLI"

    with tempfile.TemporaryDirectory(prefix="esw-integration-") as temporary:
        probe = Path(temporary)
        first = probe / "user_card.esw"
        second = probe / "user-card.hesw"
        first.write_text("<p>First</p>")
        second.write_text("<p>Second</p>")
        output = probe / "generated.swift"
        output.write_text("previous output")
        diagnostic = run([compiler, "--batch", "--root", probe, "--output", output, first, second], succeeds=False)
        assert "both generate renderUserCard" in diagnostic
        assert output.read_text() == "previous output", "Failed batches must not replace existing output"
        malformed = probe / "invalid.hesw"
        malformed.write_text("<div>\n<span>\n</div>")
        diagnostic = run([compiler, malformed], succeeds=False)
        assert f"{malformed}:3:1: error:" in diagnostic and "expected </span>" in diagnostic
        print("Batch collisions, atomic output, and template diagnostics passed.", flush=True)

        prefix = """import ESW
struct Row { let name: String }
struct Attributes { let count: Int }
struct ProbeTable: ESWComponent {
    static func render(entry: [ESWSlot<Attributes, Row>]) -> String { "" }
}
"""
        invalid_templates = [
            ('<.probe-table><:entry count="wrong" :let={row}>{row.name}</:entry></.probe-table>', "expected argument type 'Int'"),
            ('<.probe-table><:entry count={1} :let={row}>{row.missing}</:entry></.probe-table>', "has no member 'missing'"),
            ('<.probe-table><:entry count={row.name.count} :let={row}>{row.name}</:entry></.probe-table>', "cannot find 'row' in scope"),
            ('<.probe-table />', "missing argument for parameter 'entry'"),
        ]
        for index, (template, expected) in enumerate(invalid_templates):
            source = probe / f"invalid-slot-{index}.swift"
            source.write_text(prefix + 'let html = #hesw(#"' + template + '"#)\n')
            diagnostic = run(["swiftc", "-typecheck", *includes, *plugin, source], succeeds=False)
            assert expected in diagnostic, diagnostic
        print("Swift rejects wrong slot attributes, wrong row members, escaped binding scopes, and missing required slots.", flush=True)

        typed_template = probe / "typed.esw"
        companion = probe / "TypedView.swift"
        typed_output = probe / "typed-generated.swift"
        companion.write_text('import ESW\n@ESWTemplate("typed.esw")\nstruct TypedView { let email: String }\n')
        typed_template.write_text('<p><%= emali %></p>\n')
        run([compiler, typed_template, "--view-source", companion, "--source-location", "--output", typed_output])
        diagnostic = run(["swiftc", "-typecheck", *includes, *plugin, companion, typed_output], succeeds=False)
        assert "cannot find 'emali' in scope" in diagnostic, diagnostic
        assert str(typed_template) + ":1:" in diagnostic, diagnostic
        typed_template.write_text('<p><%= email %></p>\n')
        run([compiler, typed_template, "--view-source", companion, "--output", typed_output])
        caller = probe / "main.swift"
        caller.write_text("let html = TypedView(email: 42).render()\n")
        diagnostic = run(["swiftc", "-typecheck", *includes, *plugin, companion, typed_output, caller], succeeds=False)
        assert "expected argument type 'String'" in diagnostic, diagnostic
        companion.write_text('import ESW\n@ESWTemplate("typed.esw")\npublic struct TypedView { let email = "public"; public init() {} }\n')
        run([compiler, typed_template, "--view-source", companion, "--output", typed_output])
        run(["swiftc", "-emit-module", "-module-name", "ViewProbe", *includes, *plugin,
             companion, typed_output, "-o", probe / "ViewProbe.swiftmodule"])
        caller.write_text("import ViewProbe\nlet html = TypedView().render()\n")
        run(["swiftc", "-typecheck", *includes, "-I", probe, caller])
        print("Typed views preserve Swift input checking, template diagnostics, and public access across modules.", flush=True)

        previous_output = typed_output.read_bytes()
        duplicate = probe / "DuplicateView.swift"
        duplicate.write_text('import ESW\n@ESWTemplate("typed.esw")\nstruct DuplicateView {}\n')
        diagnostic = run([compiler, typed_template, "--view-source", companion,
                          "--view-source", duplicate, "--output", typed_output], succeeds=False)
        assert "already associated" in diagnostic, diagnostic
        assert typed_output.read_bytes() == previous_output
        diagnostic = run([compiler, "--batch", "--view-source", companion,
                          "--output", typed_output], succeeds=False)
        assert "missing or is not a template input" in diagnostic, diagnostic
        assert typed_output.read_bytes() == previous_output
        diagnostic = run(["swiftc", "-typecheck", *includes, *plugin, companion], succeeds=False)
        assert "does not conform to protocol 'ESWView'" in diagnostic, diagnostic
        print("Missing templates, duplicate associations, and missing build output fail without replacing generated files.", flush=True)

        if options.roost:
            cli = options.roost.resolve() / "Sources/RoostCLI"
            generator = probe / "generator-probe"
            run([
                "swiftc", cli / "Utils/FieldParser.swift", cli / "Templates/GeneratorTemplates.swift",
                cli / "Templates/AuthTemplates.swift", cli / "Templates/ProjectTemplates.swift",
                ROOT / "Fixtures/PeregrineGeneratorProbe.swift", "-o", generator,
            ])
            generated = probe / "roost"
            run([generator, generated])
            templates = sorted((generated / "Views").rglob("*.esw"))
            generated_swift = generated / "ESWTemplates.swift"
            view_sources = sorted((generated / "Views").rglob("*.swift"))
            source_args = [arg for path in view_sources for arg in ("--view-source", path)]
            run([compiler, "--batch", "--root", generated, "--output", generated_swift, *source_args, *templates])
            run(["swiftc", "-frontend", "-parse", generated_swift, *view_sources, *sorted((generated / "Routes").glob("*.swift"))])
            for variant in ("true", "false"):
                run(["swift", "package", "--package-path", generated / f"manifest-{variant}", "dump-package"])
            print("Roost generator output passes ESW compilation, Swift syntax checks, and manifest evaluation.", flush=True)

    fixture = ROOT / "Fixtures/PluginConsumer"
    run(["swift", "run", "--disable-sandbox", "App"], cwd=fixture)
    template = fixture / "Sources/App/Views/posts/index.esw"
    original = template.read_bytes()
    marker = "ESW_INCREMENTAL_PROBE_7DADF281"
    modified = original + f"\n<p>{marker}</p>\n".encode()
    try:
        template.write_bytes(modified)
        run(["swift", "run", "--disable-sandbox", "App", marker], cwd=fixture)
    finally:
        if template.read_bytes() != modified:
            raise RuntimeError("The incremental probe template changed concurrently; refusing to overwrite it")
        template.write_bytes(original)
    run(["swift", "run", "--disable-sandbox", "App"], cwd=fixture)
    print("Consumer runtime assertions and template-only incremental rebuild passed; source restored.", flush=True)

    typed_template = fixture / "Sources/App/Views/registration.esw"
    companion = typed_template.parent / "RegistrationView.swift"
    original_template = typed_template.read_bytes()
    original_companion = companion.read_bytes()
    marker = "ESW_TYPED_INCREMENTAL_PROBE_86A99341"
    modified_template = original_template + f"\n<p>{marker}</p>\n".encode()
    modified_companion = original_companion.replace(b"struct RegistrationView", b"public struct RegistrationView", 1)
    assert modified_companion != original_companion
    companion_changed = False
    try:
        typed_template.write_bytes(modified_template)
        run(["swift", "run", "--disable-sandbox", "App", "--typed-template", marker], cwd=fixture)
        companion.write_bytes(modified_companion)
        companion_changed = True
        run(["swift", "run", "--disable-sandbox", "App", "--typed-template", marker], cwd=fixture)
        outputs = list((fixture / ".build/plugins/outputs").rglob("ESWTemplates.swift"))
        assert any("extension RegistrationView {\n    public func render()" in path.read_text()
                   for path in outputs), "A view-source-only edit must regenerate the method visibility"
    finally:
        if typed_template.read_bytes() != modified_template:
            raise RuntimeError("Typed template changed concurrently; refusing to overwrite it")
        typed_template.write_bytes(original_template)
        if companion_changed:
            if companion.read_bytes() != modified_companion:
                raise RuntimeError("Companion changed concurrently; refusing to overwrite it")
            companion.write_bytes(original_companion)
    run(["swift", "run", "--disable-sandbox", "App"], cwd=fixture)
    print("Typed template-only and view-source-only incremental rebuilds passed; sources restored.", flush=True)


if __name__ == "__main__":
    main()
