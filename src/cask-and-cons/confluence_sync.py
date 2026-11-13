#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["playwright", "beautifulsoup4"]
# ///
"""Mirror Confluence Cloud spaces to local Markdown files.

Driven by environment variables set by `maak' (see confluence.scm):
  CONFLUENCE_BASE_URL   https://acme.atlassian.net
  CONFLUENCE_AUTH       "browser" (reuse a logged-in Chrome profile) or "token"
  CONFLUENCE_PROFILE    Chrome profile directory        (browser mode)
  CONFLUENCE_CHANNEL    playwright channel, e.g. chrome (browser mode)
  CONFLUENCE_EMAIL / CONFLUENCE_TOKEN                   (token mode)
  CONFLUENCE_SPACES     space keys, space separated; empty = all
  CONFLUENCE_DEST       target directory
  CONFLUENCE_DELAY      "min max" seconds to wait between requests (default "2 5")
  CONFLUENCE_RAW_DIR    (debug) also save the raw storage-format XHTML here

Usage: confluence_sync.py login | sync

The mirror is exact: pages deleted in Confluence disappear locally.
Requests are strictly sequential, paced with random pauses, and back off on
HTTP 429/5xx (honouring Retry-After).
"""
import base64
import collections
import html
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

from bs4 import BeautifulSoup, NavigableString

BASE = os.environ["CONFLUENCE_BASE_URL"].rstrip("/")
AUTH = os.environ.get("CONFLUENCE_AUTH", "browser")
PROFILE = os.environ.get("CONFLUENCE_PROFILE", "")
CHANNEL = os.environ.get("CONFLUENCE_CHANNEL", "chrome")
DELAY = tuple(float(x) for x in os.environ.get("CONFLUENCE_DELAY", "2 5").split())
PAGE_SIZE = 50
START = time.monotonic()


class AuthError(Exception):
    pass


# ---------------------------------------------------------------- reporting

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def elapsed():
    s = int(time.monotonic() - START)
    return f"{s // 3600}h{s % 3600 // 60:02d}m{s % 60:02d}s" if s >= 3600 else f"{s // 60}m{s % 60:02d}s"


def notify(msg):
    subprocess.run(
        ["osascript", "-e", f'display notification "{msg}" with title "caco confluence"'],
        check=False,
    )


# ------------------------------------------------------------------ browser

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


# ------------------------------------------------------------------ fetching

class Fetcher:
    """Sequential, human-paced GETs returning parsed JSON."""

    def __init__(self, stack):
        self.last = None
        self.count = 0
        if AUTH == "token":
            cred = base64.b64encode(
                f"{os.environ['CONFLUENCE_EMAIL']}:{os.environ['CONFLUENCE_TOKEN']}".encode()
            ).decode()

            def fetch(url):
                req = urllib.request.Request(
                    url, headers={"Authorization": f"Basic {cred}",
                                  "Accept": "application/json"})
                try:
                    with urllib.request.urlopen(req, timeout=90) as r:
                        return r.status, r.read(), dict(r.headers)
                except urllib.error.HTTPError as e:
                    return e.code, e.read(), dict(e.headers)
        else:
            from playwright.sync_api import sync_playwright

            p = stack.enter_context(sync_playwright())
            ctx = launch(p, headless=True)
            stack.callback(ctx.close)

            def fetch(url):
                r = ctx.request.get(url, headers={"Accept": "application/json"},
                                    timeout=90000)
                return r.status, r.body(), {k.lower(): v for k, v in r.headers.items()}

        self._fetch = fetch

    def _pace(self):
        if self.last is not None:
            wait = random.uniform(*DELAY)
            # Now and then, "stop to read" for a bit longer.
            if self.count % 10 == 0:
                wait += random.uniform(5, 15)
            remaining = wait - (time.monotonic() - self.last)
            if remaining > 0:
                time.sleep(remaining)

    def get(self, url):
        for attempt in range(6):
            self._pace()
            status, body, headers = self._fetch(url)
            self.last = time.monotonic()
            self.count += 1
            if status == 429 or status >= 500:
                try:
                    wait = float(headers.get("retry-after") or headers.get("Retry-After"))
                except (TypeError, ValueError):
                    wait = 30 * 2 ** attempt
                wait = min(wait, 600) + random.uniform(0, 5)
                log(f"  HTTP {status}; backing off {wait:.0f}s (attempt {attempt + 1}/6)")
                time.sleep(wait)
                continue
            if status in (401, 403):
                raise AuthError(f"HTTP {status}")
            try:
                return json.loads(body)
            except ValueError:  # HTML: redirected to the SSO login page
                raise AuthError("got a login page instead of JSON")
        raise RuntimeError(f"giving up on {url}")

    def paged(self, url):
        """Yield (result, batch_number) for every item of a paginated endpoint."""
        batch = 0
        while url:
            page = self.get(url)
            batch += 1
            for item in page["results"]:
                yield item, batch
            nxt = page.get("_links", {}).get("next")
            url = BASE + nxt if nxt else None


# ---------------------------------------------------------------- conversion

CODE_MACROS = {"code", "noformat"}
PANELS = {"info": "Info", "note": "Note", "warning": "Warning", "tip": "Tip",
          "success": "Success", "error": "Error", "panel": None}
UNWRAP_MACROS = {"expand", "ui-expand", "details", "section", "column",
                 "excerpt", "excerpt-include", "div", "span", "multiexcerpt",
                 "content-block", "aside", "view-file", "table-processor",
                 "table-joiner", "table-filter", "table-excerpt",
                 "table-excerpt-include", "toc-zone", "numberedheadings",
                 "html-bobswift", "spreadsheet-table"}
DROP_MACROS = {"toc", "children", "pagetree", "recently-updated", "anchor",
               "livesearch", "contentbylabel", "page-index", "chart",
               "profile-picture", "space-details", "attachments",
               "tasks-report-macro", "change-history", "profile",
               "create-from-template", "popular-labels", "contributors-summary",
               "pagetreesearch", "widget", "content-report-table",
               "detailssummary", "calendar", "roadmap", "jirachart",
               "table-chart", "gallery", "multimedia", "code", "noformat"}
CODE_RE = re.compile(
    r'<ac:structured-macro\b[^>]*?ac:name="(code|noformat)"[^>]*>(.*?)</ac:structured-macro>',
    re.S)
CDATA_RE = re.compile(r"<!\[CDATA\[(.*?)\]\]>", re.S)
LANG_RE = re.compile(r'<ac:parameter\s+ac:name="language">(.*?)</ac:parameter>', re.S)
LANG_MAP = {"js": "javascript", "c#": "csharp", "c++": "cpp", "none": "",
            "yml": "yaml", "sh": "bash", "shell": "bash"}
BLOCKS = ("p", "div", "ul", "ol", "li", "pre", "blockquote", "h1", "h2", "h3",
          "h4", "h5", "h6", "table")


def _code_block(m):
    kind, inner = m.group(1), m.group(2)
    lang = ""
    if kind == "code":
        lm = LANG_RE.search(inner)
        lang = lm.group(1).strip().lower() if lm else ""
        lang = LANG_MAP.get(lang, lang)
    body = "".join(CDATA_RE.findall(inner))
    if not body:  # plain-text-body without CDATA
        pm = re.search(r"<ac:plain-text-body>(.*?)</ac:plain-text-body>", inner, re.S)
        body = html.unescape(pm.group(1)) if pm else ""
    cls = f' class="language-{lang}"' if lang else ""
    tm = re.search(r'<ac:parameter\s+ac:name="title">(.*?)</ac:parameter>', inner, re.S)
    title = f"<p><strong>{tm.group(1).strip()}</strong></p>" if tm and tm.group(1).strip() else ""
    return f"{title}<pre><code{cls}>{html.escape(body.strip(chr(10)))}</code></pre>"


def _text(soup, text):
    return NavigableString(text)


def _swap(el, soup, html_fragment):
    new = BeautifulSoup(html_fragment, "html.parser")
    el.replace_with(*list(new.contents)) if new.contents else el.decompose()


def _unwrap_body(el):
    body = el.find("ac:rich-text-body", recursive=False)
    if body is not None:
        el.replace_with(*list(body.contents)) if body.contents else el.decompose()
    else:
        el.decompose()


def _macro(el, soup, stats):
    name = (el.get("ac:name") or "").lower()
    params = {p.get("ac:name"): p.get_text() for p in el.find_all("ac:parameter", recursive=False)}
    body = el.find("ac:rich-text-body", recursive=False)
    if name in PANELS:
        label = params.get("title") or PANELS[name]
        bq = soup.new_tag("blockquote")
        if label:
            p = soup.new_tag("p")
            strong = soup.new_tag("strong")
            strong.string = label
            p.append(strong)
            bq.append(p)
        if body is not None:
            for ch in list(body.contents):
                bq.append(ch)
        el.replace_with(bq)
    elif name == "status":
        el.replace_with(NavigableString(f"[{params.get('title', '').strip()}]"))
    elif name == "jira":
        el.replace_with(NavigableString(params.get("key") or params.get("jqlQuery") or "[jira]"))
    elif name in ("expand", "ui-expand") and body is not None:
        title = params.get("title")
        pieces = []
        if title:
            p = soup.new_tag("p")
            strong = soup.new_tag("strong")
            strong.string = title
            p.append(strong)
            pieces.append(p)
        pieces.extend(list(body.contents))
        el.replace_with(*pieces)
    elif name in UNWRAP_MACROS:
        _unwrap_body(el)
    elif name in DROP_MACROS:
        el.decompose()
    else:
        stats[name or "?"] += 1
        if body is not None:
            _unwrap_body(el)
        else:
            what = (params.get("diagramName") or params.get("filename")
                    or params.get("name") or params.get("page") or "")
            em = soup.new_tag("em")
            em.string = f"[{name}: {what}]" if what else f"[{name}]"
            el.replace_with(em)


def _adf_extension(el, soup):
    """ADF extensions: keep real content (panels...), else a titled placeholder."""
    node = el.find("ac:adf-node")
    content = node.find("ac:adf-content") if node is not None else None
    if content is not None and content.get_text(strip=True):
        el.replace_with(*list(content.contents))
        return
    title = ""
    if node is not None:
        for attr in node.find_all("ac:adf-attribute", recursive=False):
            if attr.get("key") == "text":
                title = attr.get_text().strip()
        if not title:
            for par in node.find_all("ac:adf-parameter"):
                if par.get("key") == "extension-title":
                    title = par.get_text().strip()
    if title:
        em = soup.new_tag("em")
        em.string = f"[{title}]"
        el.replace_with(em)
    else:
        el.decompose()


def _link_text(el):
    body = el.find(["ac:link-body", "ac:plain-text-link-body"])
    if body is not None and body.get_text().strip():
        return body.get_text().strip()
    for tag, attr in (("ri:page", "ri:content-title"), ("ri:blog-post", "ri:content-title"),
                      ("ri:attachment", "ri:filename"), ("ri:space", "ri:space-key"),
                      ("ri:user", "ri:account-id")):
        ref = el.find(tag)
        if ref is not None:
            return ref.get(attr) or ""
    return el.get("ac:anchor") or ""


BR = "CACOBR"  # line-break token: pandoc cannot put <br> inside pipe-table cells


def _flatten_cell(cell, soup):
    """Reduce table-cell content to inline text with BR tokens between lines,
    so pandoc can write it as a pipe table (BR becomes <br> afterwards)."""
    for t in cell.find_all("table"):
        t.replace_with(NavigableString(t.get_text(" ", strip=True)))
    for pre in cell.find_all("pre"):
        lines = [ln for ln in pre.get_text().strip("\n").split("\n") if ln.strip()]
        holder = soup.new_tag("span")
        for k, ln in enumerate(lines):
            if k:
                holder.append(NavigableString(BR))
            code = soup.new_tag("code")
            code.string = ln.strip()
            holder.append(code)
        pre.replace_with(holder)
    for li in cell.find_all("li"):
        li.insert(0, NavigableString("\u2022 "))
        li.append(NavigableString(BR))
        li.unwrap()
    for lst in cell.find_all(["ul", "ol"]):
        lst.unwrap()
    for blk in cell.find_all(["p", "div", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"]):
        if blk.get_text(strip=True) or blk.find(["img", "a", "code"]):
            blk.append(NavigableString(BR))
        blk.unwrap()
    for br in cell.find_all(["br", "hr"]):
        br.replace_with(NavigableString(BR))


def _normalize_table(table, soup):
    for t in table.find_all(["colgroup", "col", "caption"]):
        t.decompose()
    rows = [r for r in table.find_all("tr") if r.find_parent("table") is table]
    if not rows:
        table.decompose()
        return
    # Expand colspan / rowspan into a rectangular grid.
    grid = []
    pending = {}  # column -> (remaining rows, tag name)
    for r in rows:
        cells = [c for c in r.find_all(["td", "th"], recursive=False)]
        new_row, col = [], 0
        queue = list(cells)
        while queue or col in pending:
            if col in pending:
                left, name = pending[col]
                filler = soup.new_tag(name)
                new_row.append(filler)
                if left <= 1:
                    del pending[col]
                else:
                    pending[col] = (left - 1, name)
                col += 1
                continue
            c = queue.pop(0)
            try:
                cs = max(1, int(c.get("colspan", 1)))
                rs = max(1, int(c.get("rowspan", 1)))
            except ValueError:
                cs = rs = 1
            _flatten_cell(c, soup)
            new_row.append(c)
            for k in range(1, cs):
                new_row.append(soup.new_tag(c.name))
            if rs > 1:
                for k in range(cs):
                    pending[col + k] = (rs - 1, c.name)
            col += cs
        grid.append((r, new_row))
    width = max(len(cells) for _, cells in grid)
    for i, (r, cells) in enumerate(grid):
        while len(cells) < width:
            cells.append(soup.new_tag("td"))
        r.clear()
        for c in cells:
            c.attrs = {}
            c.name = "th" if i == 0 else "td"  # pipe tables need a header row
            r.append(c)
    # Rebuild as a plain thead/tbody table.
    thead, tbody = soup.new_tag("thead"), soup.new_tag("tbody")
    for i, (r, _) in enumerate(grid):
        (thead if i == 0 else tbody).append(r.extract())
    table.clear()
    table.attrs = {}
    table.append(thead)
    if tbody.contents:
        table.append(tbody)


def clean(storage, stats):
    """Turn Confluence storage-format XHTML into plain HTML pandoc handles well."""
    storage = CODE_RE.sub(_code_block, storage)
    soup = BeautifulSoup(storage, "html.parser")

    for el in reversed(soup.find_all("ac:adf-extension")):
        _adf_extension(el, soup)
    for el in soup.find_all(["ac:adf-attribute", "ac:adf-parameter", "ac:adf-node"]):
        el.decompose()
    for el in reversed(soup.find_all("ac:structured-macro")):
        _macro(el, soup, stats)
    for el in soup.find_all("ac:emoji"):
        el.replace_with(NavigableString(el.get("ac:emoji-fallback") or el.get("ac:shortname") or ""))
    for el in soup.find_all("ac:link"):
        txt = _link_text(el)
        el.replace_with(NavigableString(txt)) if txt else el.decompose()
    for el in soup.find_all("ac:image"):
        att, url = el.find("ri:attachment"), el.find("ri:url")
        if url is not None and url.get("ri:value"):
            img = soup.new_tag("img", src=url["ri:value"], alt=el.get("ac:alt", ""))
            el.replace_with(img)
        else:
            name = att.get("ri:filename") if att is not None else el.get("ac:alt", "")
            em = soup.new_tag("em")
            em.string = f"[image: {name}]"
            el.replace_with(em)
    for task_list in soup.find_all("ac:task-list"):
        ul = soup.new_tag("ul")
        for task in task_list.find_all("ac:task"):
            done = (task.find("ac:task-status") or soup.new_tag("x")).get_text().strip() == "complete"
            body = task.find("ac:task-body")
            li = soup.new_tag("li")
            li.append(NavigableString("☑ " if done else "☐ "))
            if body is not None:
                for ch in list(body.contents):
                    li.append(ch)
            ul.append(li)
        task_list.replace_with(ul)
    for el in soup.find_all("time"):
        el.replace_with(NavigableString(el.get("datetime", "")))
    for el in soup.find_all(["ac:placeholder", "ac:parameter", "ac:adf-fallback", "ac:hint"]):
        el.decompose()
    for el in soup.find_all(re.compile(r"^ri:")):
        el.decompose()
    for el in soup.find_all(re.compile(r"^ac:")):  # layouts, adf, comment markers, ...
        el.unwrap()
    for table in soup.find_all("table"):
        if table.find_parent("table") is None:
            _normalize_table(table, soup)
    for el in soup.find_all(True):
        keep = {k: v for k, v in el.attrs.items()
                if k in ("href", "src", "alt") or (k == "class" and el.name == "code")}
        el.attrs = keep
    return str(soup)


def to_markdown(storage, stats):
    out = subprocess.run(
        ["pandoc", "-f", "html-native_divs-native_spans", "-t", "gfm-raw_html",
         "--wrap=none"],
        input=clean(storage, stats), capture_output=True, text=True, check=True,
    ).stdout
    if "[TABLE]" in out:  # pandoc could not express a table as a pipe table
        stats["<table-fallback>"] += 1
    # Tidy line-break tokens inside table cells, then make them real <br>s.
    out = re.sub(r"\|\s*(?:CACOBR\s*)+", "| ", out)
    out = re.sub(r"(?:\s*CACOBR)+\s*\|", " |", out)
    out = re.sub(r"(?:\s*CACOBR){2,}", BR, out)
    out = re.sub(r"\s*CACOBR\s*", "<br>", out)
    out = re.sub(r"[ \t]+\n", "\n", out)
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip() + "\n"


# ---------------------------------------------------------------------- sync

def slug(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:80] or "untitled"


def write_page(out, pg, key, stats, raw_dir):
    storage = pg.get("body", {}).get("storage", {}).get("value", "")
    if raw_dir:
        (raw_dir / f"{pg['id']}.xml").write_text(storage)
    try:
        md = to_markdown(storage, stats)
    except subprocess.CalledProcessError as e:
        log(f"  ! pandoc failed on '{pg['title']}' ({pg['id']}): {e.stderr.strip()[:120]}")
        stats["<pandoc-failure>"] += 1
        md = "_Conversion failed; see Confluence._\n"
    head = ("---\n"
            f"title: {json.dumps(pg['title'], ensure_ascii=False)}\n"
            f"confluence_id: {pg['id']}\n"
            f"space: {key}\n"
            f"updated: {pg.get('version', {}).get('createdAt', '')}\n"
            f"url: {BASE}/wiki/spaces/{key}/pages/{pg['id']}\n"
            "---\n\n")
    (out / f"{slug(pg['title'])}-{pg['id']}.md").write_text(head + md)


def mirror(stage, dest):
    """rsync the staged tree over dest; return (added, changed, deleted)."""
    dest.mkdir(parents=True, exist_ok=True)
    res = subprocess.run(
        ["rsync", "-a", "-c", "--delete", "--exclude", ".git", "--itemize-changes",
         f"{stage}/", f"{dest}/"],
        capture_output=True, text=True, check=True)
    added = changed = deleted = 0
    for line in res.stdout.splitlines():
        if line.startswith("*deleting"):
            deleted += 1
        elif line.startswith(">f") or line.startswith("<f"):
            if "+++++" in line[:11]:
                added += 1
            else:
                changed += 1
    return added, changed, deleted


def sync():
    from contextlib import ExitStack

    want = set(os.environ.get("CONFLUENCE_SPACES", "").split())
    dest = Path(os.environ["CONFLUENCE_DEST"]).expanduser()
    raw = os.environ.get("CONFLUENCE_RAW_DIR")
    raw_dir = Path(raw) if raw else None
    if raw_dir:
        raw_dir.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp())
    stats = collections.Counter()
    per_space = {}
    try:
        with ExitStack() as stack:
            fetcher = Fetcher(stack)
            log(f"Listing spaces on {BASE} (pause {DELAY[0]:g}-{DELAY[-1]:g}s between requests)")
            spaces = [s for s, _ in fetcher.paged(f"{BASE}/wiki/api/v2/spaces?limit=250")
                      if not want or s["key"] in want]
            log(f"{len(spaces)} space(s) to mirror: {', '.join(s['key'] for s in spaces)}")
            total = 0
            for i, s in enumerate(spaces, 1):
                key = s["key"]
                out = stage / key
                out.mkdir()
                n, last_batch = 0, 0
                t0 = time.monotonic()
                log(f"[{i}/{len(spaces)}] {key}: starting")
                url = (f"{BASE}/wiki/api/v2/spaces/{s['id']}/pages"
                       f"?body-format=storage&limit={PAGE_SIZE}")
                for pg, batch in fetcher.paged(url):
                    if batch != last_batch and last_batch:
                        log(f"[{i}/{len(spaces)}] {key}: {n} pages so far "
                            f"({fetcher.count} requests, {elapsed()} elapsed)")
                    last_batch = batch
                    write_page(out, pg, key, stats, raw_dir)
                    n += 1
                total += n
                per_space[key] = n
                log(f"[{i}/{len(spaces)}] {key}: done, {n} pages in "
                    f"{time.monotonic() - t0:.0f}s ({total} total)")
        if not total:
            sys.exit(f"nothing fetched; refusing to touch {dest}")
        added, changed, deleted = mirror(stage, dest)
        log(f"Synced to {dest}")
        log(f"  {total} pages in {len(per_space)} space(s): "
            f"{added} new, {changed} changed, {deleted} removed, "
            f"{total - added - changed} unchanged")
        macros = {k: v for k, v in stats.items() if not k.startswith("<")}
        if macros:
            log("  unhandled macros (kept as text): " +
                ", ".join(f"{k}×{v}" for k, v in stats.most_common() if k in macros))
        if stats["<pandoc-failure>"]:
            log(f"  {stats['<pandoc-failure>']} page(s) failed to convert")
        if stats["<table-fallback>"]:
            log(f"  {stats['<table-fallback>']} page(s) have a table pandoc could not write as Markdown")
        log(f"Finished in {elapsed()} ({fetcher.count} requests)")
    finally:
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sync"
    try:
        login() if cmd == "login" else sync()
    except AuthError as e:
        notify("Session expired - run: maak login-confluence")
        sys.exit(f"Not authenticated ({e}). Run `maak login-confluence`.")
