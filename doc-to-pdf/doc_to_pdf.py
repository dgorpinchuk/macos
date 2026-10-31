#!/usr/bin/env python3
"""Finder Quick Action: Word -> PDF, fixed staging paths, URL-friendly output."""
import fcntl
import re
import shutil
import subprocess
import sys
import unicodedata
from contextlib import contextmanager
from pathlib import Path

STAGING_ROOT = Path.home() / 'Library/Application Support/DocToPDF'
SCRIPT = Path(__file__).with_name('convert_word.applescript')
VALID_EXTENSIONS = {'.doc', '.docx'}


def clean_stem(stem):
    stem = unicodedata.normalize('NFC', stem)
    normalized = ''.join(c if (c.isalnum() or c == '_') else '_' for c in stem)
    normalized = re.sub(r'_+', '_', normalized).strip('_') or 'document'
    while len(normalized.encode('utf-8')) > 170:
        normalized = normalized[:-1].rstrip('_')
    return normalized or 'document'


@contextmanager
def exclusive_work_area():
    STAGING_ROOT.mkdir(parents=True, exist_ok=True)
    with (STAGING_ROOT / '.conversion.lock').open('a+b') as handle:
        # Only one converter may reuse source.docx/source.doc and output.pdf at once.
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def convert_file(source):
    source = Path(source).expanduser().absolute()
    if not source.is_file() or source.suffix.lower() not in VALID_EXTENSIONS:
        return 'skipped', f'{source}: not a DOC/DOCX file'

    staged_doc = STAGING_ROOT / ('source' + source.suffix.lower())
    staged_pdf = STAGING_ROOT / 'output.pdf'

    # Write into one fixed staging directory; no per-document subdirectories.
    try:
        with source.open('rb') as src, staged_doc.open('wb') as dst:
            shutil.copyfileobj(src, dst)

        staged_pdf.unlink(missing_ok=True)  # never accept a stale PDF from a prior run
        result = subprocess.run(
            ['/usr/bin/osascript', str(SCRIPT), str(staged_doc), str(staged_pdf)],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            err = (result.stderr or result.stdout).strip()
            raise RuntimeError(f'Word conversion failed: {err or result.returncode}')
        if not staged_pdf.is_file() or staged_pdf.stat().st_size == 0:
            raise RuntimeError('Word did not produce a nonempty PDF')

        stem = clean_stem(source.stem)
        for index in range(1, 100000):
            suffix = '' if index == 1 else f'_{index}'
            target = source.parent / f'{stem}{suffix}.pdf'
            try:
                with target.open('xb') as output, staged_pdf.open('rb') as pdf:
                    try:
                        shutil.copyfileobj(pdf, output)
                    except BaseException:
                        output.close()
                        target.unlink(missing_ok=True)
                        raise
                return 'ok', f'{source.name} → {target.name}'
            except FileExistsError:
                continue
        raise RuntimeError('Too many conflicting output filenames')

    finally:
        # Cleanup even when Word fails or the destination cannot be written.
        # The fixed parent directory and lock file remain in place.
        for temporary_file in (staged_doc, staged_pdf):
            temporary_file.unlink(missing_ok=True)


def main(argv):
    if not SCRIPT.is_file():
        print(f'Missing AppleScript: {SCRIPT}', file=sys.stderr)
        return 2
    if not argv:
        print('Select one or more DOC/DOCX files in Finder.', file=sys.stderr)
        return 2
    ok = failed = skipped = 0
    details = []
    with exclusive_work_area():
        for filename in argv:
            try:
                status, message = convert_file(filename)
                if status == 'ok':
                    ok += 1
                else:
                    skipped += 1
            except Exception as exc:
                failed += 1
                message = f'{filename}: {exc}'
            details.append(message)
    summary = f'PDF: {ok} converted, {failed} failed, {skipped} skipped'
    print(summary + '\n' + '\n'.join(details))
    if failed:
        subprocess.run(['/usr/bin/osascript', '-e',
            'on run argv\n display dialog (item 1 of argv) with title "Convert to PDF" buttons {"OK"} default button "OK"\nend run',
            summary + '\n\n' + '\n'.join(details)[:1500]], check=False)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
