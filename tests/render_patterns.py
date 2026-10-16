import html
import struct
import zlib
from pathlib import Path

from test_patterns import PATTERN_DIR, PatternTests, PRESET_LIMITS, load_library, read_png


ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = ROOT / "test_sources" / "output"
PRESET_NAMES = {0: "balanced", 1: "detail", 2: "bold"}
SAMPLE_NAMES = {1: "nearest", 0: "area"}
PREVIEW_SIZE = 128


def png_chunk(kind, data):
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))


def write_png(path, width, height, pixels):
    rows = b"".join(
        b"\0" + pixels[y * width * 4 : (y + 1) * width * 4]
        for y in range(height)
    )
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(rows))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def main():
    renderer = PatternTests()
    renderer.library = load_library()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    cards = []
    markdown_sections = [
        "# Pixel-art conversion results",
        "",
        "Generated with `python tests/render_patterns.py` from the official test-pattern corpus.",
        f"Square patterns use a {PREVIEW_SIZE}x{PREVIEW_SIZE} output grid; odd-size patterns use their source grid.",
        "",
    ]
    pattern_paths = sorted(PATTERN_DIR.glob("*.png"))
    for path in pattern_paths:
        width, height, pixels = read_png(path)
        image = (width, height, pixels, path.name)
        if path.stem.startswith("15_odd_size_"):
            target_width, target_height = width, height
        else:
            target_width, target_height = PREVIEW_SIZE, PREVIEW_SIZE
        cards.append(f"<h2>{html.escape(path.name)}</h2><div class=\"grid\">")
        markdown_sections.extend(
            [
                "<details>",
                f"<summary>{path.name}</summary>",
                "",
                "<table>",
                "<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>",
                "<tbody>",
            ]
        )
        for preset, limit in PRESET_LIMITS.items():
            markdown_sections.append(
                f"<tr><th>{PRESET_NAMES[preset]} ({limit} colors)</th>"
            )
            for sample_mode, sample_name in SAMPLE_NAMES.items():
                label = f"{PRESET_NAMES[preset]} / {sample_name} / max {limit} colors"
                filename = f"{path.stem}--{PRESET_NAMES[preset]}-{sample_name}.png"
                output = renderer.convert(
                    image,
                    target_width,
                    target_height,
                    preset=preset,
                    sample_mode=sample_mode,
                )
                write_png(OUTPUT_DIR / filename, target_width, target_height, output)
                cards.append(
                    f'<figure><figcaption>{html.escape(label)}</figcaption>'
                    f'<a href="{html.escape(filename)}"><img src="{html.escape(filename)}" '
                    f'alt="{html.escape(label)}"></a></figure>'
                )
                markdown_sections.append(
                    f'<td><a href="{filename}"><img src="{filename}" '
                    f'alt="{label}" width="160"></a></td>'
                )
            markdown_sections.append("</tr>")
        markdown_sections.extend(["</tbody>", "</table>", "", "</details>", ""])
        cards.append("</div>")

    gallery = (
        "<!doctype html><html><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        "<title>madeitpx pattern previews</title><style>"
        "body{font:14px system-ui,sans-serif;margin:24px;background:#202124;color:#eee}"
        "h2{margin-top:32px}.grid{display:grid;grid-template-columns:repeat(3,minmax(180px,1fr));gap:12px}"
        "figure{margin:0;padding:10px;background:#303134}figcaption{margin-bottom:8px}"
        "img{display:block;width:100%;height:auto;image-rendering:pixelated}"
        "@media(max-width:640px){.grid{grid-template-columns:repeat(2,minmax(130px,1fr))}}"
        "</style></head><body><h1>madeitpx pattern previews</h1>"
        "<p>Generated from the official test_sources corpus. Square patterns use a "
        f"{PREVIEW_SIZE}x{PREVIEW_SIZE} output grid; odd-size patterns use their source grid.</p>"
        + "\n".join(cards)
        + "</body></html>"
    )
    (OUTPUT_DIR / "index.html").write_text(gallery, encoding="utf-8")
    (OUTPUT_DIR / "results.md").write_text(
        "\n".join(markdown_sections) + "\n",
        encoding="utf-8",
    )
    print(f"Rendered {len(pattern_paths)} patterns to {OUTPUT_DIR}")
    print(f"Generated {len(pattern_paths) * len(PRESET_NAMES) * len(SAMPLE_NAMES)} PNG previews.")


if __name__ == "__main__":
    main()
