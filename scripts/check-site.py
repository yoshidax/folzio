#!/usr/bin/env python3
"""Check the website in site/ before it is published with GitHub Pages.

    scripts/check-site.py [--release] [SITE_DIR]   (default: site)

1. Every English page (SITE_DIR/*.html) has a Japanese page at the same path under ja/, and the reverse.
2. Each pair has the same skeleton: the elements in <body> with their class and id,
   ignoring inline text elements, which differ between the translations.
3. Each page declares its language, local references point to files inside SITE_DIR,
   and scripts are loaded only from local files.
4. With --release, placeholder media (media/placeholder/) must no longer be referenced.
"""
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
import sys
from urllib.parse import urlsplit

# Inline elements that carry translated text and may differ between the two languages.
INLINE = {'a', 'abbr', 'b', 'br', 'code', 'em', 'i', 'kbd', 'small', 'span', 'strong', 'wbr'}
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr'}
REFERENCE_ATTRIBUTES = {'href', 'src', 'poster'}
PLACEHOLDER = 'media/placeholder/'


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lang = None
        self.in_body = False
        self.skeleton = []
        self.references = []
        self.external_scripts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'html':
            self.lang = attrs.get('lang')
        if tag == 'body':
            self.in_body = True
        for name in REFERENCE_ATTRIBUTES:
            value = attrs.get(name)
            if value is not None:
                self.references.append(value)
        if tag == 'script' and attrs.get('src') and urlsplit(attrs['src']).scheme:
            self.external_scripts.append(attrs['src'])
        if self.in_body and tag not in INLINE:
            self.skeleton.append(f"{tag} class={attrs.get('class', '')} id={attrs.get('id', '')}")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag == 'body':
            self.in_body = False
        if self.in_body and tag not in INLINE and tag not in VOID:
            self.skeleton.append(f'/{tag}')


def parse(path):
    page = Page()
    page.feed(path.read_text(encoding='utf-8'))
    page.close()
    return page


def local_target(site, page_path, reference):
    parts = urlsplit(reference)
    if parts.scheme or parts.netloc or reference.startswith(('#', 'mailto:')):
        return None
    if not parts.path:
        return None
    relative = PurePosixPath(page_path.parent.relative_to(site).as_posix()) / parts.path
    target = (site / relative).resolve()
    if parts.path.endswith('/'):
        target = target / 'index.html'
    return target


def check(site, release=False):
    site = Path(site)
    errors = []
    notes = []
    if not site.is_dir():
        return [f'{site} not found'], notes
    root = site.resolve()
    english = {path.name for path in site.glob('*.html')}
    japanese = {path.name for path in (site / 'ja').glob('*.html')}
    for name in sorted(english - japanese):
        errors.append(f'{site}/{name} has no Japanese page at {site}/ja/{name}')
    for name in sorted(japanese - english):
        errors.append(f'{site}/ja/{name} has no English page at {site}/{name}')

    placeholders = set()
    for name in sorted(english & japanese):
        pages = {}
        for lang, path in (('en', site / name), ('ja', site / 'ja' / name)):
            page = parse(path)
            pages[lang] = page
            if page.lang != lang:
                errors.append(f'{path}: <html lang> must be "{lang}" (found {page.lang!r})')
            for script in page.external_scripts:
                errors.append(f'{path}: load scripts from local files only ({script})')
            for reference in page.references:
                target = local_target(site, path, reference)
                if target is None:
                    continue
                if not target.is_relative_to(root):
                    errors.append(f'{path}: {reference} points outside {site}')
                elif not target.is_file():
                    errors.append(f'{path}: {reference} not found')
                if PLACEHOLDER in reference:
                    placeholders.add(reference.rsplit('/', 1)[-1])
        en, ja = pages['en'].skeleton, pages['ja'].skeleton
        if en != ja:
            for index, (left, right) in enumerate(zip(en + [''] * len(ja), ja + [''] * len(en))):
                if left != right:
                    errors.append(f'{site}/{name} and {site}/ja/{name} differ in structure at element {index + 1}: '
                                  f'{left or "(end)"} / {right or "(end)"}')
                    break

    if placeholders:
        message = 'placeholder media still referenced: ' + ', '.join(sorted(placeholders))
        (errors if release else notes).append(message)
    return errors, notes


def main(argv):
    release = '--release' in argv
    args = [arg for arg in argv if arg != '--release']
    if len(args) > 1 or any(arg.startswith('-') for arg in args):
        print('Usage: check-site.py [--release] [SITE_DIR]', file=sys.stderr)
        return 2
    site = Path(args[0]) if args else Path(__file__).resolve().parents[1] / 'site'
    errors, notes = check(site, release)
    for note in notes:
        print(f'note: {note}')
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print(f'{site.name}: pages are in sync')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
