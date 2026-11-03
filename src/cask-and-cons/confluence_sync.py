#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright"]
# ///
"""Mirror Confluence Cloud spaces to local Markdown files.

Driven by environment variables set by `caco' (see confluence.scm):
  CONFLUENCE_BASE_URL   https://acme.atlassian.net
  CONFLUENCE_AUTH       "browser" (reuse a logged-in Chrome profile) or "token"
  CONFLUENCE_PROFILE    Chrome profile directory        (browser mode)
  CONFLUENCE_CHANNEL    playwright channel, e.g. chrome (browser mode)
  CONFLUENCE_EMAIL / CONFLUENCE_TOKEN                   (token mode)
  CONFLUENCE_SPACES     space keys, space separated; empty = all
  CONFLUENCE_DEST       target directory

Usage: confluence_sync.py login | sync

The mirror is exact: pages deleted in Confluence disappear locally.
"""
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = os.environ["CONFLUENCE_BASE_URL"].rstrip("/")
AUTH = os.environ.get("CONFLUENCE_AUTH", "browser")
PROFILE = os.environ.get("CONFLUENCE_PROFILE", "")
CHANNEL = os.environ.get("CONFLUENCE_CHANNEL", "chrome")


class AuthError(Exception):
    pass


def notify(msg):
    subprocess.run(
        ["osascript", "-e", f'display notification "{msg}" with title "caco confluence"'],
        check=False,
    )


def slug(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:80]


def launch(p, headless):
    return p.chromium.launch_persistent_context(
        PROFILE, channel=CHANNEL, headless=headless
    )


def login():
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        ctx = launch(p, headless=False)
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.goto(f"{BASE}/wiki/")
        print("Log in (SSO/MFA) in the browser window, then press Enter here.")
        input()
        r = ctx.request.get(f"{BASE}/wiki/api/v2/spaces?limit=1",
                            headers={"Accept": "application/json"})
        ok = r.status == 200
        ctx.close()
    if not ok:
        sys.exit("Login did not give API access (HTTP %s)." % r.status)
    print("Session saved in", PROFILE)


def make_getter(stack):
    """Return get(url) -> parsed JSON, for the configured auth mode."""
    if AUTH == "token":
        cred = base64.b64encode(
            f"{os.environ['CONFLUENCE_EMAIL']}:{os.environ['CONFLUENCE_TOKEN']}".encode()
        ).decode()

        def fetch(url):
            req = urllib.request.Request(
                url, headers={"Authorization": f"Basic {cred}",
                              "Accept": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return r.status, r.read()
            except urllib.error.HTTPError as e:
                return e.code, e.read()
    else:
        from playwright.sync_api import sync_playwright

        p = stack.enter_context(sync_playwright())
        ctx = launch(p, headless=True)
        stack.callback(ctx.close)

        def fetch(url):
            r = ctx.request.get(url, headers={"Accept": "application/json"})
            return r.status, r.body()

    def get(url):
        for attempt in range(5):
            status, body = fetch(url)
            if status == 429 or status >= 500:
                time.sleep(2 ** attempt)
                continue
            if status in (401, 403):
                raise AuthError(f"HTTP {status}")
            try:
                return json.loads(body)
            except ValueError:  # HTML: redirected to the SSO login page
                raise AuthError("got a login page instead of JSON")
        raise RuntimeError(f"giving up on {url}")

    return get


def paged(get, url):
    while url:
        page = get(url)
        yield from page["results"]
        nxt = page.get("_links", {}).get("next")
        url = BASE + nxt if nxt else None


def sync():
    from contextlib import ExitStack

    want = set(os.environ.get("CONFLUENCE_SPACES", "").split())
    dest = Path(os.environ["CONFLUENCE_DEST"])
    stage = Path(tempfile.mkdtemp())
    try:
        with ExitStack() as stack:
            get = make_getter(stack)
            spaces = [s for s in paged(get, f"{BASE}/wiki/api/v2/spaces?limit=250")
                      if not want or s["key"] in want]
            for s in spaces:
                out = stage / s["key"]
                out.mkdir()
                n = 0
                url = (f"{BASE}/wiki/api/v2/spaces/{s['id']}/pages"
                       "?body-format=storage&limit=100")
                for pg in paged(get, url):
                    html = pg.get("body", {}).get("storage", {}).get("value", "")
                    md = subprocess.run(
                        ["pandoc", "-f", "html", "-t", "gfm", "--wrap=none"],
                        input=html, capture_output=True, text=True, check=True,
                    ).stdout
                    title = pg["title"].replace('"', '\\"')
                    head = (f'---\ntitle: "{title}"\nconfluence_id: {pg["id"]}\n'
                            f'space: {s["key"]}\n'
                            f'updated: {pg.get("version", {}).get("createdAt", "")}\n'
                            f'url: {BASE}/wiki/spaces/{s["key"]}/pages/{pg["id"]}\n---\n\n')
                    (out / f"{slug(pg['title'])}-{pg['id']}.md").write_text(head + md)
                    n += 1
                print(f"space {s['key']}: {n} pages")
        if not any(stage.iterdir()):
            sys.exit(f"nothing fetched; refusing to wipe {dest}")
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.run(["rsync", "-a", "--delete", "--exclude", ".git",
                        f"{stage}/", f"{dest}/"], check=True)
        print("synced to", dest)
    finally:
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sync"
    try:
        login() if cmd == "login" else sync()
    except AuthError as e:
        notify("Session expired - run: caco login-confluence")
        sys.exit(f"Not authenticated ({e}). Run `caco login-confluence`.")
