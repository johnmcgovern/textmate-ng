# TextMate-NG branding

App icon assets for the **TextMate-NG** fork. Kept in the superproject (not in the
`../icons/` git submodule, which is upstream `textmate/document-icons`), so we can
version our own branding without touching the submodule.

## Files
- `TextMate-NG.icns` — **primary app icon** (referenced by `Info.plist`
  `CFBundleIconFile = TextMate-NG`). Copied into `Contents/Resources/` by the app's
  `files branding/*.icns … "Resources"` rule in `../default.rave`.
- `TextMate-NG_1024.png` — the 1024×1024 master the `.icns` is built from.
- `render-icon.swift` — the generator.
- `legacy/TextMate.icns` — backup of the previous app icon (the classic upstream
  purple daisy) at the time of the switch. The pristine original also remains
  untouched in the `../icons/` submodule.

## Design
macOS 26 ("Liquid Glass") style: TextMate's heritage purple daisy composited on a
full-bleed superellipse (squircle) tile with a soft lavender gradient, a glass
sheen, and two glossy pill badges — red **Alpha** (pre-release marker, top-right)
and purple **NG** (fork marker, bottom-right).

## Regenerate
```bash
# 1. extract the flower artwork from the current upstream icon (alpha preserved)
sips -s format png ../icons/TextMate.icns --out flower.png --resampleWidth 1024
# 2. render the 1024 master
swift render-icon.swift flower.png TextMate-NG_1024.png
# 3. build the iconset + .icns
mkdir -p TextMate-NG.iconset
for s in 16 32 128 256 512; do
  sips -s format png TextMate-NG_1024.png --out "TextMate-NG.iconset/icon_${s}x${s}.png"    --resampleWidth "$s"          >/dev/null
  sips -s format png TextMate-NG_1024.png --out "TextMate-NG.iconset/icon_${s}x${s}@2x.png" --resampleWidth "$((s*2))"   >/dev/null
done
iconutil -c icns TextMate-NG.iconset -o TextMate-NG.icns
```
