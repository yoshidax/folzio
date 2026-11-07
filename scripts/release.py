#!/usr/bin/env python3
"""Validate committed release requests and create immutable draft releases."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote
import zipfile

NUMBER = r'(0|[1-9][0-9]*)'
VERSION = NUMBER + r'\.' + NUMBER + r'\.' + NUMBER
SHA = re.compile(r'[0-9a-f]{40}')
PUBLIC_REPO = 'yoshidax/folzio'


def run(*args, cwd=None, env=None, binary=False, data=None):
    result = subprocess.run([str(x) for x in args], cwd=cwd, env=env, input=data,
                            capture_output=True, text=not binary)
    if result.returncode:
        raise ValueError(f'{args[0]} failed: {result.stderr.decode() if binary else result.stderr}')
    return result.stdout if binary else result.stdout.strip()


def git(root, *args):
    return run('git', '-C', root, *args)


def require_sha(value):
    if not isinstance(value, str) or not SHA.fullmatch(value):
        raise ValueError('A complete lowercase commit SHA is required')
    return value


def validate_numbers(version, build):
    if not isinstance(version, str) or not re.fullmatch(VERSION, version):
        raise ValueError('Version must be canonical X.Y.Z (no leading zeros)')
    if not isinstance(build, str) or not re.fullmatch(NUMBER, build):
        raise ValueError('Build number must be canonical digits (no leading zeros)')


def json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def blob(root, sha, path, optional=False):
    require_sha(sha)
    git(root, 'rev-parse', '--verify', sha + '^{commit}')
    entry = git(root, 'ls-tree', sha, '--', path)
    if not entry:
        if optional:
            return None
        raise ValueError(f'Committed file missing: {path}')
    if entry.split()[0] not in ('100644', '100755'):
        raise ValueError(f'Not a committed regular file: {path}')
    return run('git', '-C', root, 'show', f'{sha}:{path}', binary=True)


def load_request(root, commit=None):
    root = Path(root).resolve()

    def read(path):
        if commit:
            for parent in PurePosixPath(path).parents:
                if str(parent) != '.':
                    entry = git(root, 'ls-tree', commit, '--', str(parent))
                    if not entry or entry.split()[0] != '040000':
                        raise ValueError(f'Not a committed directory: {parent}')
            return blob(root, commit, path)
        file = root / path
        current = root
        for part in PurePosixPath(path).parts:
            current = current / part
            if current.is_symlink():
                raise ValueError('Symbolic links are not release inputs')
        if not file.is_file():
            raise ValueError(f'Regular file missing: {path}')
        return file.read_bytes()

    request = json.loads(read('release.json').decode('utf-8'), object_pairs_hook=json_object)
    if not isinstance(request, dict) or set(request) != {'version', 'build_number', 'notes_file'}:
        raise ValueError('release.json must contain exactly version, build_number, notes_file')
    validate_numbers(request['version'], request['build_number'])
    notes = request['notes_file']
    if not isinstance(notes, str) or not re.fullmatch(r'release-notes/[A-Za-z0-9_./-]+\.md', notes):
        raise ValueError('notes_file must be a relative Markdown path under release-notes/')
    if any(p in ('', '.', '..') for p in notes.split('/')):
        raise ValueError('Invalid notes path component')
    if not read(notes).decode('utf-8').strip():
        raise ValueError('Release notes are empty')
    return request


class APIError(ValueError):
    """A failed API call must never be interpreted as an absent resource."""


class GitHub:
    def __init__(self, repo):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
            raise ValueError('Invalid repository')
        self.repo = repo

    def api(self, path, method='GET', data=None, missing=False):
        endpoint = f'repos/{self.repo}/{path}'
        args = ['gh', 'api', '--include', '--method', method, endpoint]
        if data is not None:
            args += ['--input', '-']
        result = subprocess.run(args, input=None if data is None else json.dumps(data),
                                text=True, capture_output=True)
        status = re.search(r'^HTTP/\S+ (\d+)', result.stdout, re.M)
        if not status:
            raise APIError(f'GitHub API transport failed: {method} {path}')
        code = int(status.group(1))
        if code == 404 and missing:
            return None
        if result.returncode or code >= 400:
            raise APIError(f'GitHub API {code}: {method} {path}')
        _, separator, body = result.stdout.partition('\n\n')
        if not separator:
            raise APIError('Malformed GitHub API response')
        try:
            return json.loads(body) if body.strip() else None
        except ValueError as error:
            raise APIError('Invalid GitHub API JSON') from error

    def pages(self, path, key=None):
        result = []
        page = 1
        separator = '&' if '?' in path else '?'
        while True:
            value = self.api(f'{path}{separator}per_page=100&page={page}')
            if key:
                value = value[key]
            if not isinstance(value, list):
                raise ValueError('Expected paginated list')
            result += value
            if len(value) < 100:
                return result
            page += 1


def tag_commit(api, tag):
    ref = api.api('git/ref/tags/' + quote(tag, safe=''), missing=True)
    if ref is None:
        return None
    obj = ref['object']
    for _ in range(10):
        require_sha(obj['sha'])
        if obj['type'] == 'commit':
            return obj['sha']
        if obj['type'] != 'tag':
            break
        obj = api.api('git/tags/' + obj['sha'])['object']
    raise ValueError('Tag does not resolve to a commit')


def existing_release(api, tag):
    # The tag endpoint only returns published releases; the authenticated list also includes drafts.
    return next((item for item in api.pages('releases') if item['tag_name'] == tag), None)


def require_unused_version(api, version):
    tag = 'v' + version
    if existing_release(api, tag) is not None or tag_commit(api, tag) is not None:
        raise ValueError(f'Version {version} is already used in the public repository')


def check_release_state(api, tag, sha):
    if existing_release(api, tag) is not None:
        raise ValueError('Release already exists; inspect and repair the draft manually')
    target = tag_commit(api, tag)
    if target is not None and target != sha:
        raise ValueError('Existing tag points to a different commit')
    return target


def verify_assets(directory, version):
    directory = Path(directory)
    asset = f'Folzio-v{version}-macos-arm64.zip'
    archive = directory / asset
    sums = directory / 'SHA256SUMS'
    if archive.is_symlink() or sums.is_symlink() or not archive.is_file() or not sums.is_file():
        raise ValueError('Release ZIP and checksum must be regular files')
    expected = hashlib.sha256(archive.read_bytes()).hexdigest() + '  ' + asset + '\n'
    if sums.read_text() != expected:
        raise ValueError('Checksum does not match ZIP')
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        if not names or any(not n.startswith('Folzio.app/') or '..' in n.split('/') or '\\' in n
                            for n in names):
            raise ValueError('ZIP must contain only Folzio.app')
        if 'Folzio.app/Contents/MacOS/Folzio' not in names:
            raise ValueError('ZIP executable is missing')
    return archive, sums


def output(values):
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            for key, value in values.items():
                text = str(value).lower() if isinstance(value, bool) else str(value)
                if '\n' in text or '\r' in text:
                    raise ValueError('Multiline workflow output refused')
                stream.write(f'{key}={text}\n')
    print(json.dumps(values, ensure_ascii=False))


def summary(text):
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(text + '\n')


def public_context(root):
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if os.environ.get('GITHUB_REPOSITORY') != PUBLIC_REPO:
        raise ValueError('Not the public repository')
    if event['repository']['default_branch'] != 'main' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise ValueError('Public releases require the default branch main')
    sha = require_sha(os.environ.get('GITHUB_SHA'))
    if git(root, 'rev-parse', 'HEAD') != sha:
        raise ValueError('Checkout does not match the event SHA')
    if os.environ.get('GITHUB_EVENT_NAME') not in ('push', 'workflow_dispatch'):
        raise ValueError('Unsupported release event')
    return event, sha


def public_plan(root, api):
    event, sha = public_context(root)
    raw = blob(root, sha, 'release.json', optional=True)
    if raw is None:
        if os.environ['GITHUB_EVENT_NAME'] == 'push':
            return dict(ready=False, reason='No release request', commit=sha)
        raise ValueError('Manual release requires release.json')
    request = load_request(root, sha)
    if os.environ['GITHUB_EVENT_NAME'] == 'push':
        before = require_sha(event['before'])
        previous = None if before == '0' * 40 else blob(root, before, 'release.json', optional=True)
        if previous == raw:
            return dict(ready=False, reason='Release request unchanged', commit=sha)
    tag = 'v' + request['version']
    check_release_state(api, tag, sha)
    return dict(ready=True, commit=sha, tag=tag, **request)


def public_draft(root, directory, api):
    _, sha = public_context(root)
    request = load_request(root, sha)
    tag = 'v' + request['version']
    archive, sums = verify_assets(directory, request['version'])
    if check_release_state(api, tag, sha) is None:
        try:
            api.api('git/refs', 'POST', dict(ref='refs/tags/' + tag, sha=sha))
        except ValueError:
            if tag_commit(api, tag) != sha:
                raise
    if tag_commit(api, tag) != sha:
        raise ValueError('Tag verification failed')
    if existing_release(api, tag) is not None:
        raise ValueError('Release was created concurrently; existing assets are unchanged')
    url = f'https://github.com/{PUBLIC_REPO}/actions/runs/{os.environ["GITHUB_RUN_ID"]}'
    notes = blob(root, sha, request['notes_file']).decode('utf-8')
    notes += f'\n\n---\nCommit: {sha}\nVersion: {request["version"]}\nBuild: {request["build_number"]}\nRun: {url}\n'
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / 'notes.md'
        path.write_text(notes)
        try:
            run('gh', 'release', 'create', tag, archive, sums, '--repo', PUBLIC_REPO,
                '--verify-tag', '--draft', '--title', f'Folzio {tag}', '--notes-file', path)
        except ValueError as error:
            raise ValueError('Draft creation/upload failed; inspect the tag and draft before retrying') from error
    summary(f'Draft {tag}: {sha}\n\nBuild {request["build_number"]}\n\n{sums.read_text()}\n{url}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['request', 'numbers', 'assets', 'plan', 'draft'])
    parser.add_argument('arguments', nargs='*')
    args = parser.parse_args()
    root = Path.cwd()
    if args.operation == 'numbers':
        validate_numbers(*args.arguments)
    elif args.operation == 'request':
        request = load_request(root if not args.arguments else Path(args.arguments[0]))
        output(dict(tag='v' + request['version'], **request))
    elif args.operation == 'assets':
        verify_assets(*args.arguments)
    elif args.operation == 'plan':
        result = public_plan(root, GitHub(PUBLIC_REPO))
        output(result)
        summary(f'Release plan: {result}')
    else:
        public_draft(root, args.arguments[0], GitHub(PUBLIC_REPO))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile) as error:
        summary(f'Release failed: {error}')
        sys.exit(1)
