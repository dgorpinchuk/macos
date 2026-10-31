#!/usr/bin/env python3
from __future__ import annotations
import os
import re
import sys
import unicodedata
from pathlib import Path

MAX_STEM_BYTES = 170


def clean_stem(value: str) -> str:
    value = unicodedata.normalize('NFC', value)
    result = re.sub(r'_+', '_', ''.join(c if c.isalnum() or c == '_' else '_' for c in value)).strip('_') or 'item'
    while len(result.encode('utf-8')) > MAX_STEM_BYTES:
        result = result[:-1].rstrip('_')
    return result or 'item'


def normalized_name(path: Path) -> str | None:
    name = path.name
    if name.startswith('.'):
        return None  # leave hidden macOS / Unix items alone
    if path.is_dir() and not path.is_symlink():
        return clean_stem(name)
    extension = path.suffix
    if extension and not (extension[1:].isalnum() and len(extension) <= 16):
        extension = ''
    stem = name[:-len(extension)] if extension else name
    return clean_stem(stem) + extension


def same_file(a: Path, b: Path) -> bool:
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False


def rename(path: Path) -> str:
    if not path.exists() and not path.is_symlink():
        return f'SKIP (not found): {path}'
    proposed = normalized_name(path)
    if proposed is None:
        return f'SKIP (hidden): {path}'
    if proposed == path.name:
        return f'OK (already normalized): {path}'

    ext = path.suffix if (not path.is_dir() or path.is_symlink()) else ''
    if ext and not (ext[1:].isalnum() and len(ext) <= 16):
        ext = ''
    normalized_stem = proposed[:-len(ext)] if ext else proposed
    index = 1
    while True:
        suffix = '' if index == 1 else f'_{index}'
        stem = normalized_stem
        while len((stem + suffix).encode('utf-8')) > MAX_STEM_BYTES:
            stem = stem[:-1].rstrip('_')
        candidate = path.with_name(stem + suffix + ext)
        # Compare names as well as identity, to handle case-only renames on case-insensitive APFS.
        if not (candidate.exists() or candidate.is_symlink()) or same_file(candidate, path):
            break
        index += 1
    path.rename(candidate)
    return f'RENAMED: {path.name} -> {candidate.name}'


def main(argv: list[str]) -> int:
    if not argv:
        print('No Finder items were supplied.', file=sys.stderr)
        return 2
    # Children first: a selected parent can be renamed without invalidating selected descendants.
    paths = sorted({os.path.abspath(os.path.expanduser(p)) for p in argv}, key=lambda p: (-len(Path(p).parts), p))
    errors = 0
    changed = 0
    skipped = 0
    for value in paths:
        try:
            outcome = rename(Path(value))
            print(outcome)
            if outcome.startswith('RENAMED:'):
                changed += 1
            else:
                skipped += 1
        except (OSError, ValueError) as exc:
            errors += 1
            print(f'ERROR: {value}: {exc}', file=sys.stderr)
    print(f'Finished: renamed {changed}, unchanged/skipped {skipped}, errors {errors}.')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
