# Convert Images — macOS Finder Quick Action

Convert multiple Finder-selected images to a chosen format without external dependencies. Originals remain unchanged. Requires macOS with `/usr/bin/sips`, `/usr/bin/osascript` and Python 3.9+.

## Installation

1. Place `convert_images.py` and `choose_format.applescript` together in `~/scripts/convert-images/`.
2. Verify Python: `/usr/bin/python3 --version` (3.9+ required). On macOS without Python 3, install it and change the Automator interpreter path.
3. Automator → New Document → Quick Action.
   - Workflow receives current: **files or folders** (or **image files**, if available)
   - In: **Finder**
   - Action: **Run Shell Script**
   - Shell: `/bin/zsh`
   - Pass input: **as arguments**
4. Enter:

   ```zsh
   /usr/bin/python3 "$HOME/scripts/convert-images/convert_images.py" "$@"
   ```

5. Save as `Convert Images`. Automator saves it in `~/Library/Services/Convert Images.workflow`.

## Behavior

- The format chooser runs once per batch, with formats discovered from `sips --formats` on **your** Mac.
- Supports any readable raster image format that macOS `sips` can decode, including many RAW formats. Unsupported files and folders are skipped. No recursive folder scanning.
- Outputs are next to the originals; existing files are never overwritten. Conflicts get `_2`, `_3`, etc.
- Existing source extension and filename stem are preserved; the target extension is canonicalized (`.jpg`, `.png`, etc.). Same-format inputs are skipped.
- Image pixel width and height are verified. If changing the format would change the dimensions, conversion fails safely.
- File modification/access times and POSIX permissions are copied where feasible.
- A report summarizes successes, skipped files, and failures.

## Important limitations

- **Metadata is best effort**: `sips` may preserve some EXIF and ICC profile information but cannot promise lossless preservation of EXIF, XMP, IPTC, GPS, orientation, or color profiles across all format pairs. Check important metadata in the converted output. The script does not independently copy all metadata tags.
- Color space, alpha transparency, bit depth, animation and multipage layers **may be lost or changed** on conversion to a format that cannot represent them. JPEG does not support transparency; GIF may lose colors/animation; PDF and PSD may be flattened. Pixel dimensions alone do not guarantee visual equivalence.
- WebP is commonly **readable but not writable** via `sips` even on recent macOS releases. It will not appear as an output unless you use a different conversion backend. AVIF output depends on the macOS version.
- Very large or RAW images may take longer to process. No recursive conversion or quality slider is provided in this version.
- `sips --formats` determines the actual available output choices; do not assume all formats listed in the code are available on every Mac.

## Troubleshooting

- Confirm `sips --formats` shows writable formats.
- Confirm `/usr/bin/python3 --version` is 3.9 or newer.
- If Quick Action is not visible in Finder, enable it in System Settings / Extensions / Finder or Finder Quick Actions settings (UI varies by macOS version).
- Run a trial on copies of non-sensitive images and inspect pixel dimensions, colors and metadata.
