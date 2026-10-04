#!/usr/bin/env python3
"""Compile real consumers, reject invalid slot types, and verify incremental builds.

Usage: python3 scripts/check_integration.py [--peregrine /path/to/Peregrine]
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
    parser.add_argument("--peregrine", type=Path)
    options = parser.parse_args()
    run(["swift", "build", "--product", "ESWCompilerCLI"])
    binary_dir = Path(run(["swift", "build", "--show-bin-path"]).strip())
    compiler = binary_dir / "ESWCompilerCLI"

    with tempfile.TemporaryDirectory(prefix="esw-integration-") as temporary:
        probe = Path(temporary)
        first = probe / "user_card.esw"
        second = probe / "user-card.heex"
        first.write_text("<p>First</p>")
        second.write_text("<p>Second</p>")
        output = probe / "generated.swift"
        output.write_text("previous output")
        diagnostic = run([compiler, "--batch", "--root", probe, "--output", output, first, second], succeeds=False)
        assert "both generate renderUserCard" in diagnostic
        assert output.read_text() == "previous output", "Failed batches must not replace existing output"
        malformed = probe / "invalid.heex"
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
            source.write_text(prefix + 'let html = #heex(#"' + template + '"#)\n')
            diagnostic = run([
                "swiftc", "-typecheck", "-I", binary_dir, "-load-plugin-executable",
                str(binary_dir / "ESWMacros") + "#ESWMacros", source,
            ], succeeds=False)
            assert expected in diagnostic, diagnostic
        print("Swift rejects wrong slot attributes, wrong row members, escaped binding scopes, and missing required slots.", flush=True)

        if options.peregrine:
            cli = options.peregrine.resolve() / "Sources/PeregrineCLI"
            generator = probe / "generator-probe"
            run([
                "swiftc", cli / "Utils/FieldParser.swift", cli / "Templates/GeneratorTemplates.swift",
                cli / "Templates/AuthTemplates.swift", cli / "Templates/ProjectTemplates.swift",
                ROOT / "Fixtures/PeregrineGeneratorProbe.swift", "-o", generator,
            ])
            generated = probe / "peregrine"
            run([generator, generated])
            templates = sorted((generated / "Views").rglob("*.esw"))
            generated_swift = generated / "ESWTemplates.swift"
            run([compiler, "--batch", "--root", generated, "--output", generated_swift, *templates])
            run(["swiftc", "-frontend", "-parse", generated_swift, *sorted((generated / "Routes").glob("*.swift"))])
            for variant in ("true", "false"):
                run(["swift", "package", "--package-path", generated / f"manifest-{variant}", "dump-package"])
            print("Peregrine generator output passes ESW compilation, Swift syntax checks, and manifest evaluation.", flush=True)

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


if __name__ == "__main__":
    main()
