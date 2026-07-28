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
- `variants/` — alternate 1024×1024 renders kept for reference (not shipped).
  Each differs from the primary only in the tile gradient (step 1 in
  `render-icon.swift`); swap the three colors below into the `bg` gradient and
  re-render to reproduce:
  - **teal-mid** (current primary): `c(150,236,228), c(42,187,186), c(10,122,138)`
  - **teal-deep** (`TextMate-NG_1024_teal-deep.png`): `c(70,200,200), c(20,140,155), c(4,80,105)`
  - **teal-light** (`TextMate-NG_1024_teal-light.png`): `c(214,250,244), c(150,224,216), c(84,180,184)`

## Design
macOS 26 ("Liquid Glass") style: TextMate's heritage purple daisy (enlarged to
90% of the tile) composited on a full-bleed superellipse (squircle) tile with a
teal liquid-glass gradient, a glass sheen, a refracted bottom rim light, and two
glossy pill badges — red **Alpha** (pre-release marker, top-right) and purple
**NG** (fork marker, bottom-right). The teal ground is deliberate: upstream
TextMate's icon sits on white/lavender, so NG reads instantly in the Dock and
in side-by-side comparisons.

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
