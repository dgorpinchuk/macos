#!/usr/bin/env python3
"""Finder Quick Action: convert selected images using built-in macOS sips."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SIPS = '/usr/bin/sips'
OSASCRIPT = '/usr/bin/osascript'

# Labels, format token supported by sips, canonical extension, possible UTI identifiers.
FORMATS = [
    ('JPEG (.jpg)', 'jpeg', '.jpg', ('public.jpeg',)),
    ('PNG (.png)', 'png', '.png', ('public.png',)),
    ('HEIC (.heic)', 'heic', '.heic', ('public.heic',)),
    ('TIFF (.tiff)', 'tiff', '.tiff', ('public.tiff',)),
    ('GIF (.gif)', 'gif', '.gif', ('com.compuserve.gif',)),
    ('BMP (.bmp)', 'bmp', '.bmp', ('com.microsoft.bmp',)),
    ('JPEG 2000 (.jp2)', 'jp2', '.jp2', ('public.jpeg-2000',)),
    ('AVIF (.avif)', 'avif', '.avif', ('public.avif',)),
    ('PDF (.pdf)', 'pdf', '.pdf', ('com.adobe.pdf',)),
    ('PSD (.psd)', 'psd', '.psd', ('com.adobe.photoshop-image',)),
    ('TGA (.tga)', 'tga', '.tga', ('com.truevision.tga-image',)),
]


def writable_formats():
    result = subprocess.run([SIPS, '--formats'], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or 'sips --formats failed')
    lines = result.stdout.splitlines()
    writable = set()
    for label, token, ext, ids in FORMATS:
        # sips --formats gives entries like: public.png (Writable) png
        for line in lines:
            lower = line.lower()
            if 'writable' not in lower:
                continue
            if any(re.search(r'(?<![a-z0-9])' + re.escape(identifier.lower()) + r'(?![a-z0-9])', lower) for identifier in ids):
                writable.add(label)
                break
            # Some OS versions use output format names instead of UTIs.
            if re.search(r'\b' + re.escape(token) + r'\b', lower):
                writable.add(label)
                break
    return [f for f in FORMATS if f[0] in writable]


def notify(title, message):
    # AppleScript dialog instead of notifications so Finder users see a summary.
    subprocess.run([OSASCRIPT, '-e',
                    'on run argv\n display dialog (item 2 of argv) with title (item 1 of argv) buttons {"OK"} default button "OK"\nend run',
                    title, message[:1800]], capture_output=True, text=True)


def select_format(formats):
    labels = [f[0] for f in formats]
    if not labels:
        raise RuntimeError('No supported writable image formats were detected by sips.')
    result = subprocess.run([OSASCRIPT, str(SCRIPT_DIR / 'choose_format.applescript'), *labels],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or 'Format chooser failed')
    chosen = result.stdout.strip()
    if chosen == 'CANCEL' or not chosen:
        return None
    return next((f for f in formats if f[0] == chosen), None)


def dimensions(path):
    p = subprocess.run([SIPS, '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None
    m1 = re.search(r'pixelWidth:\s*(\d+)', p.stdout)
    m2 = re.search(r'pixelHeight:\s*(\d+)', p.stdout)
    return (int(m1.group(1)), int(m2.group(1))) if m1 and m2 else None


def candidate_name(source, suffix):
    """Reserve a destination using O_EXCL to avoid overwriting existing files."""
    stem = source.stem
    counter = 1
    while True:
        name = stem + ('' if counter == 1 else '_' + str(counter)) + suffix
        dest = source.with_name(name)
        try:
            fd = os.open(str(dest), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.close(fd)
            return dest
        except FileExistsError:
            counter += 1


def main(paths):
    sources = []
    seen = set()
    for raw in paths:
        p = Path(raw).absolute()
        if p in seen:
            continue
        seen.add(p)
        if p.is_file() and not p.is_symlink():
            sources.append(p)
    if not sources:
        notify('Преобразование', 'Не выбрано файлов для конвертации.')
        return 0

    fmt = select_format(writable_formats())
    if fmt is None:
        return 0
    label, token, suffix, _ = fmt
    ok = 0
    skipped = 0
    errors = []
    for source in sources:
        # No need to duplicate files already in the requested format.
        if source.suffix.lower() == suffix or (token == 'jpeg' and source.suffix.lower() in ('.jpg', '.jpeg')) or (token == 'tiff' and source.suffix.lower() in ('.tif', '.tiff')):
            skipped += 1
            continue
        before = dimensions(source)
        if before is None:
            skipped += 1
            continue
        dest = None
        temp = None
        try:
            dest = candidate_name(source, suffix)
            # Write to temporary file *with matching extension* in destination folder,
            # then atomically replace the reserved placeholder on success.
            fd, name = tempfile.mkstemp(prefix='.convert_images_', suffix=suffix, dir=str(source.parent))
            os.close(fd)
            temp = Path(name)
            p = subprocess.run([SIPS, '-s', 'format', token, str(source), '--out', str(temp)],
                               capture_output=True, text=True)
            if p.returncode != 0:
                raise RuntimeError(p.stderr.strip() or p.stdout.strip() or 'sips conversion failed')
            after = dimensions(temp)
            if after != before:
                raise RuntimeError('Pixel dimensions changed: {} → {}'.format(before, after))
            # Preserve modification/access timestamps and POSIX mode where possible.
            # EXIF/IPTC/XMP metadata are not guaranteed by cross-format conversion.
            shutil.copystat(str(source), str(temp), follow_symlinks=False)
            os.replace(str(temp), str(dest))
            temp = None
            ok += 1
        except Exception as exc:
            errors.append('{}: {}'.format(source.name, exc))
        finally:
            if temp is not None:
                try:
                    temp.unlink()
                except OSError:
                    pass
            if dest is not None and dest.exists() and dest.stat().st_size == 0:
                try:
                    dest.unlink()
                except OSError:
                    pass
    summary = '{} преобразовано, {} пропущено, {} отменено. Формат: {}.'.format(ok, skipped, len(errors), label)
    if errors:
        summary += '\n\n' + '\n'.join(errors[:10])
        if len(errors) > 10:
            summary += '\n… и {} еще'.format(len(errors) - 10)
    notify('Преобразование', summary)
    return 1 if errors else 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:
        notify('Преобразование — Ошибка', str(exc))
        sys.exit(1)
