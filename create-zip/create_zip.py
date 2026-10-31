#!/usr/bin/env python3
"""Finder Quick Action: portable ZIP archives without macOS metadata junk."""
from __future__ import annotations

import os
import sys
import zipfile
from pathlib import Path

# 0 = store, 1 = fast Deflate. ZIP_STORED is the most predictable default.
COMPRESSION_LEVEL = 0

EXCLUDED_NAMES = {
    '.DS_Store', '__MACOSX', '.Spotlight-V100', '.Trashes',
    '.fseventsd', '.TemporaryItems', '.DocumentRevisions-V100',
    '.VolumeIcon.icns',
}


def excluded(name):
    return name in EXCLUDED_NAMES or name.startswith('._')


def unique_archive(parent, stem):
    candidate = parent / (stem + '.zip')
    number = 2
    while candidate.exists():
        candidate = parent / ('{}_{}.zip'.format(stem, number))
        number += 1
    return candidate


def add_to_zip(archive, source, root_name, warnings):
    if source.is_symlink():
        warnings.append('Пропущена символическая ссылка: {}'.format(source))
        return
    if excluded(source.name):
        return
    if source.is_dir():
        # Keep empty directories as explicit ZIP entries.
        rel = root_name.rstrip('/') + '/'
        archive.writestr(rel, b'')
        for child in sorted(source.iterdir(), key=lambda p: p.name.casefold()):
            add_to_zip(archive, child, rel + child.name, warnings)
    elif source.is_file():
        archive.write(str(source), arcname=root_name)
    else:
        warnings.append('Пропущен неподдерживаемый объект: {}'.format(source))


def main(argv):
    selected = []
    seen = set()
    for value in argv:
        path = Path(value).absolute()
        if path in seen:
            continue
        seen.add(path)
        if not path.exists() and not path.is_symlink():
            print('Отсутствует: {}'.format(path), file=sys.stderr)
            return 1
        selected.append(path)
    if not selected:
        print('Нет выбранных файлов или папок.', file=sys.stderr)
        return 1
    parents = {p.parent for p in selected}
    if len(parents) != 1:
        print('Выбери объекты из одной папки Finder.', file=sys.stderr)
        return 1
    parent = selected[0].parent
    stem = selected[0].stem if len(selected) == 1 and selected[0].is_file() else (selected[0].name if len(selected) == 1 else 'Archive')
    stem = stem or 'Archive'
    dest = unique_archive(parent, stem)
    warnings = []
    compression = zipfile.ZIP_STORED if COMPRESSION_LEVEL == 0 else zipfile.ZIP_DEFLATED
    try:
        # x prevents replacing an archive even if something creates it after our check.
        with zipfile.ZipFile(str(dest), 'x', compression=compression,
                             compresslevel=(None if COMPRESSION_LEVEL == 0 else COMPRESSION_LEVEL),
                             allowZip64=True) as archive:
            for item in selected:
                add_to_zip(archive, item, item.name, warnings)
        with zipfile.ZipFile(str(dest), 'r') as check:
            corrupt = check.testzip()
            if corrupt is not None:
                raise RuntimeError('Ошибка проверки файла {}'.format(corrupt))
        print('Создан: {}'.format(dest))
        for warning in warnings:
            print(warning, file=sys.stderr)
        return 0
    except Exception as exc:
        try:
            dest.unlink()
        except OSError:
            pass
        print('Ошибка создания ZIP: {}'.format(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
