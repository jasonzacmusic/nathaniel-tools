#!/usr/bin/env python3
"""
build_index.py - generate a ReaPack repository index (index.xml) for this repo.

This is a dependency-free stand-in for cfillion's `reapack-index` Ruby gem, which
cannot be built on every machine (its `rugged` dependency compiles libgit2 and
routinely fails on system Ruby / Apple silicon). The output follows the ReaPack
Index Format spec verbatim:

    https://codeberg.org/cfillion/reapack/wiki/Index-Format          (index.xml)
    https://github.com/cfillion/reapack-index/wiki/Packaging-Documentation
                                                                    (headers)

Behaviour that matters, and why:

  * Only files inside a subdirectory are indexed. Files at the repository root
    are never packages - that is the spec, not a choice.
  * The directory path becomes the ReaPack category.
  * A file carrying @noindex is skipped. Shared libraries under NPH/lib/ use
    this: they are not standalone actions, they ship as extra files of the
    package that requires them (@provides ... [nomain]).
  * @version is mandatory. A candidate file without it is an error, not a
    silent omission.
  * Download URLs are pinned to the git commit that last touched each file, so
    a released version can never change underneath a user.
  * Each <source> carries a SHA-256 multihash (0x12 0x20 + digest) computed on
    the exact blob GitHub will serve, so ReaPack verifies every download.

Usage:
    python3 tools/build_index.py [--check] [-o index.xml]

    --check   validate headers and print the package table, write nothing
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# repository configuration
# ---------------------------------------------------------------------------

REPO_OWNER = "jasonzacmusic"
REPO_NAME = "nph-reaper-suite"
DEFAULT_BRANCH = "main"

# Shown in ReaPack's repository list. Filename-friendly characters only.
INDEX_NAME = "NPH REAPER Suite"

# Repository-level links, shown in "About this repository".
REPO_LINKS = [
    ("website", None, "https://daw.nathanielschool.com"),
    ("website", "Nathaniel School of Music", "https://www.nathanielschool.com"),
]

# Directories that never contain packages. Kept in sync with .reapack-index.conf
# so the Ruby gem and this script agree on what the repository contains.
IGNORE = {
    ".git", ".github", ".impeccable",
    "docs",       # prose
    "reports",    # generated
    "site",       # the website, published separately
    "stagerig",   # generated rig data, not actions
    "tests",      # the harness is run from the action list, never installed
    "tools",      # this script and its siblings
}

RAW_URL = "https://raw.githubusercontent.com/{owner}/{repo}/{commit}/{path}"

# Package type by file extension (Packaging Documentation - "File Structure").
TYPE_BY_EXT = {
    ".lua": "script",
    ".eel": "script",
    ".py": "script",
    ".jsfx": "effect",
    ".ext": "extension",
    ".data": "data",
    ".theme": "theme",
    ".reaperlangpack": "langpack",
    ".www": "webinterface",
    ".reaperautoitem": "autoitem",
    ".rpp": "projectpl",
    ".rtracktemplate": "tracktpl",
    ".txt": "midinotenames",
    ".reaperkeymap": "keymap",
}

# @provides type options -> index.xml package types.
PROVIDES_TYPE = {
    "script": "script", "lua": "script", "eel": "script", "py": "script",
    "effect": "effect", "jsfx": "effect",
    "extension": "extension", "ext": "extension",
    "data": "data", "theme": "theme",
    "langpack": "langpack", "reaperlangpack": "langpack",
    "webinterface": "webinterface", "www": "webinterface",
    "projecttpl": "projectpl", "rpp": "projectpl",
    "tracktpl": "tracktpl", "rtracktemplate": "tracktpl",
    "midinotesnames": "midinotenames", "txt": "midinotenames",
    "autoitem": "autoitem", "reaperautoitem": "autoitem",
    "keymap": "keymap", "reaperkeymap": "keymap",
}

PLATFORMS = {
    "all", "darwin", "darwin32", "darwin64", "darwin-arm64",
    "linux", "linux32", "linux64", "linux-armv7l", "linux-aarch64",
    "windows", "win32", "win64", "windows-arm64ec",
}

SECTIONS = {
    "main", "midi_editor", "midi_inlineeditor",
    "midi_eventlisteditor", "mediaexplorer", "crossfade_editor",
}

# @description aliases, per the Packaging Documentation.
DESC_ALIASES = {
    "description", "desc", "name",
    "reascript name", "jsfx name", "theme name", "extension name",
}
LINK_ALIASES = {"link", "links", "website"}
DONATION_ALIASES = {"donation", "donate"}
SCREENSHOT_ALIASES = {"screenshot", "screenshots"}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class HeaderError(Exception):
    pass


# ---------------------------------------------------------------------------
# metadata header parser
# ---------------------------------------------------------------------------

COMMENT_PREFIX = re.compile(r"^\s*(--|//|#|;)\s?")
TAG_AT = re.compile(r"^@([A-Za-z_][\w-]*)\s*(.*)$")
TAG_COLON = re.compile(r"^([A-Za-z][\w \-]*?)\s*:\s*(.*)$")


def strip_comment(line: str) -> str | None:
    """Remove one leading comment marker. None if the line is not a comment."""
    if line.strip() in ("--[[", "--]]", "]]", "/*", "*/"):
        return ""
    m = COMMENT_PREFIX.match(line)
    if not m:
        return None
    return line[m.end():].rstrip("\n")


def parse_header(text: str) -> dict[str, str]:
    """
    Parse a ReaPack metadata header.

    Both documented syntaxes are supported: `@tag value` and `Tag name: value`.
    Tag names are case insensitive. A value continues onto following lines while
    they are indented by at least one space or tab (after comment stripping).
    Parsing stops at the first non-comment line.
    """
    tags: dict[str, str] = {}
    key: str | None = None
    for raw in text.splitlines():
        body = strip_comment(raw)
        if body is None:
            break  # code begins; the header is over
        if not body.strip():
            key = None
            continue
        indented = body[:1] in (" ", "\t")
        stripped = body.strip()

        if indented and key:
            tags[key] = (tags[key] + "\n" + stripped).strip("\n")
            continue

        m = TAG_AT.match(stripped)
        if m:
            key = m.group(1).lower()
            tags[key] = m.group(2).strip()
            continue

        m = TAG_COLON.match(stripped)
        if m and " " not in m.group(1).strip() or (m and m.group(1).lower() in DESC_ALIASES | LINK_ALIASES):
            key = m.group(1).strip().lower()
            tags[key] = m.group(2).strip()
            continue

        key = None
    return tags


def first_tag(tags: dict[str, str], names) -> str | None:
    for n in names:
        if n in tags and tags[n] != "":
            return tags[n]
    return None


def parse_links(value: str | None):
    """`[Label ]URL` per line -> (label, url). Label is everything before the URL."""
    out = []
    if not value:
        return out
    for line in value.splitlines():
        line = line.strip()
        if not line:
            continue
        m = re.search(r"(https?://\S+)$", line)
        if not m:
            continue
        url = m.group(1)
        label = line[: m.start()].strip() or None
        out.append((label, url))
    return out


# ---------------------------------------------------------------------------
# @provides
# ---------------------------------------------------------------------------

class Provided:
    def __init__(self, src_rel, target, platform, ptype, sections, url):
        self.src_rel = src_rel        # path relative to the repository root
        self.target = target          # <source file="..."> value
        self.platform = platform
        self.ptype = ptype
        self.sections = sections      # list, or None for "not in the action list"
        self.url = url                # explicit url pattern, or None


def parse_provides(value: str, pkg_dir: str, pkg_file: str):
    """
    Parse the @provides tag.

    Each line: [options] source[ > target][ url-pattern]
    Paths are relative to the directory holding the package file.
    """
    out = []
    if not value:
        return out
    for line in value.splitlines():
        line = line.strip()
        if not line:
            continue

        platform, ptype, sections = None, None, None
        explicit_main = False
        m = re.match(r"^\[([^\]]*)\]\s*(.*)$", line)
        if m:
            for opt in m.group(1).split():
                low = opt.lower()
                if low in PLATFORMS:
                    platform = low
                elif low in PROVIDES_TYPE:
                    ptype = PROVIDES_TYPE[low]
                elif low == "nomain":
                    sections, explicit_main = None, True
                elif low == "main":
                    sections, explicit_main = ["main"], True
                elif low.startswith("main="):
                    sections = [s.strip() for s in low[5:].split(",") if s.strip()]
                    for s in sections:
                        if s not in SECTIONS:
                            raise HeaderError(f"unknown action list section '{s}'")
                    explicit_main = True
                else:
                    raise HeaderError(f"unknown @provides option '{opt}'")
            line = m.group(2).strip()

        url = None
        um = re.search(r"\s(https?://\S+)$", line)
        if um:
            url = um.group(1)
            line = line[: um.start()].strip()

        if ">" in line:
            src, target = (p.strip() for p in line.split(">", 1))
        else:
            src, target = line.strip(), line.strip()

        if src in (".", pkg_file):
            src = pkg_file
            target = pkg_file if target in (".", "") else target
        if target.endswith("/"):
            target += os.path.basename(src)

        if not explicit_main:
            # "nomain" is the default for additional files.
            sections = ["main"] if src == pkg_file else None

        src_rel = os.path.normpath(os.path.join(pkg_dir, src))
        out.append(Provided(src_rel, target, platform, ptype, sections, url))
    return out


# ---------------------------------------------------------------------------
# git helpers
# ---------------------------------------------------------------------------

def git(*args: str) -> str:
    return subprocess.run(
        ["git", "-C", ROOT, *args],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


_commit_cache: dict[str, tuple[str, str]] = {}


def file_commit(path_rel: str) -> tuple[str, str]:
    """(sha, ISO-8601 UTC time) of the last commit that touched path_rel."""
    if path_rel in _commit_cache:
        return _commit_cache[path_rel]
    out = git("log", "-1", "--format=%H%x00%cI", "--", path_rel)
    if not out:
        raise HeaderError(
            f"{path_rel} has never been committed - commit it before indexing"
        )
    sha, iso = out.split("\0")
    dt = datetime.fromisoformat(iso).astimezone(timezone.utc)
    stamp = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    _commit_cache[path_rel] = (sha, stamp)
    return sha, stamp


def blob_at(commit: str, path_rel: str) -> bytes:
    return subprocess.run(
        ["git", "-C", ROOT, "show", f"{commit}:{path_rel}"],
        check=True, capture_output=True,
    ).stdout


def multihash_sha256(data: bytes) -> str:
    """Multihash, hexadecimal: 0x12 (sha2-256) 0x20 (32 bytes) + digest."""
    return "1220" + hashlib.sha256(data).hexdigest()


def raw_url(commit: str, path_rel: str) -> str:
    quoted = "/".join(urllib.parse.quote(p) for p in path_rel.split("/"))
    return RAW_URL.format(owner=REPO_OWNER, repo=REPO_NAME, commit=commit, path=quoted)


# ---------------------------------------------------------------------------
# markdown -> RTF (ReaPack renders the about section as RTF)
# ---------------------------------------------------------------------------

def to_rtf(markdown: str) -> str | None:
    try:
        res = subprocess.run(
            ["pandoc", "--from=commonmark", "--to=rtf", "--standalone"],
            input=markdown, capture_output=True, text=True, check=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    return res.stdout


# ---------------------------------------------------------------------------
# discovery
# ---------------------------------------------------------------------------

def candidates():
    """
    Yield (directory, filename) for every indexable file tracked by git.

    Enumerating the git tree rather than the working directory is deliberate:
    reapack-index indexes commits, every download URL has to point at a commit,
    and an uncommitted file simply cannot be published. It also means a dirty
    checkout never leaks half-finished work into the index.
    """
    for rel in sorted(git("ls-files").splitlines()):
        if "/" not in rel:
            continue  # root files are never packages
        if rel.split("/")[0] in IGNORE:
            continue
        if os.path.splitext(rel)[1].lower() not in TYPE_BY_EXT:
            continue
        pkg_dir, name = rel.rsplit("/", 1)
        yield pkg_dir, name


class Package:
    pass


def collect() -> list[Package]:
    packages: list[Package] = []
    targets_seen: dict[str, str] = {}

    for pkg_dir, name in candidates():
        rel = f"{pkg_dir}/{name}"
        with open(os.path.join(ROOT, rel), "r", encoding="utf-8", errors="replace") as fh:
            head = fh.read(16384)
        tags = parse_header(head)

        if "noindex" in tags or tags.get("noindex:", "").lower() == "true":
            continue

        version = tags.get("version")
        if not version:
            raise HeaderError(f"{rel}: missing the mandatory @version tag")
        if not re.search(r"\d", version.split()[0]):
            raise HeaderError(f"{rel}: @version '{version}' must contain a digit")

        pkg = Package()
        pkg.rel = rel
        pkg.dir = pkg_dir
        pkg.file = name
        pkg.category = pkg_dir
        pkg.type = TYPE_BY_EXT[os.path.splitext(name)[1].lower()]
        pkg.version = version.split()[0]
        pkg.desc = first_tag(tags, DESC_ALIASES)
        pkg.author = tags.get("author")
        pkg.changelog = tags.get("changelog")
        pkg.about = tags.get("about")
        pkg.links = parse_links(first_tag(tags, LINK_ALIASES))
        pkg.donations = parse_links(first_tag(tags, DONATION_ALIASES))
        pkg.screenshots = parse_links(first_tag(tags, SCREENSHOT_ALIASES))

        provides = parse_provides(tags.get("provides", ""), pkg_dir, name)
        is_meta = "metapackage" in tags and tags.get("metapackage", "").lower() != "false"
        if not is_meta and not any(p.src_rel == rel for p in provides):
            # "@metapackage false (the default for scripts/jsfx) implicitly adds
            # the current file to the file list with the main option."
            provides.insert(0, Provided(rel, name, None, None, ["main"], None))
        if not provides:
            raise HeaderError(f"{rel}: package has no files")
        pkg.provides = provides

        for p in provides:
            if not os.path.exists(os.path.join(ROOT, p.src_rel)):
                raise HeaderError(f"{rel}: @provides points at missing file {p.src_rel}")
            key = f"{pkg.category}/{p.target}"
            if key in targets_seen and targets_seen[key] != rel:
                raise HeaderError(
                    f"{rel}: installs '{key}', already owned by {targets_seen[key]}. "
                    "ReaPack packages have exclusive ownership over their files."
                )
            targets_seen[key] = rel

        packages.append(pkg)

    return packages


# ---------------------------------------------------------------------------
# index.xml
# ---------------------------------------------------------------------------

def add_links(parent, links, rel):
    for label, url in links:
        el = ET.SubElement(parent, "link")
        if rel != "website":
            el.set("rel", rel)
        if label:
            el.set("href", url)
            el.text = label
        else:
            el.text = url


def build(packages: list[Package]) -> ET.ElementTree:
    index = ET.Element("index", {"version": "1", "name": INDEX_NAME})

    by_category: dict[str, list[Package]] = {}
    for pkg in packages:
        by_category.setdefault(pkg.category, []).append(pkg)

    for category in sorted(by_category):
        cat_el = ET.SubElement(index, "category", {"name": category})
        for pkg in sorted(by_category[category], key=lambda p: p.file):
            attrs = {"name": pkg.file, "type": pkg.type}
            if pkg.desc:
                attrs["desc"] = pkg.desc
            rp_el = ET.SubElement(cat_el, "reapack", attrs)

            if pkg.about or pkg.links or pkg.donations or pkg.screenshots:
                meta = ET.SubElement(rp_el, "metadata")
                add_links(meta, pkg.links, "website")
                add_links(meta, pkg.donations, "donation")
                add_links(meta, pkg.screenshots, "screenshot")
                if pkg.about:
                    rtf = to_rtf(pkg.about)
                    if rtf:
                        ET.SubElement(meta, "description").text = rtf

            _, when = file_commit(pkg.rel)
            v_attrs = {"name": pkg.version}
            if pkg.author:
                v_attrs["author"] = pkg.author
            v_attrs["time"] = when
            ver_el = ET.SubElement(rp_el, "version", v_attrs)

            if pkg.changelog:
                ET.SubElement(ver_el, "changelog").text = pkg.changelog

            for p in pkg.provides:
                commit, _ = file_commit(p.src_rel)
                s_attrs = {}
                if p.target != pkg.file:
                    s_attrs["file"] = p.target
                if p.platform and p.platform != "all":
                    s_attrs["platform"] = p.platform
                if p.ptype and p.ptype != pkg.type:
                    s_attrs["type"] = p.ptype
                if p.sections:
                    s_attrs["main"] = " ".join(p.sections)
                s_attrs["hash"] = multihash_sha256(blob_at(commit, p.src_rel))
                src_el = ET.SubElement(ver_el, "source", s_attrs)
                src_el.text = p.url or raw_url(commit, p.src_rel)

    meta = ET.SubElement(index, "metadata")
    for rel, label, url in REPO_LINKS:
        el = ET.SubElement(meta, "link")
        if rel != "website":
            el.set("rel", rel)
        if label:
            el.set("href", url)
            el.text = label
        else:
            el.text = url

    readme = os.path.join(ROOT, "README.md")
    if os.path.exists(readme):
        with open(readme, encoding="utf-8") as fh:
            rtf = to_rtf(fh.read())
        if rtf:
            ET.SubElement(meta, "description").text = rtf
        else:
            sys.stderr.write(
                "warning: pandoc not found, repository about section omitted\n"
            )

    return ET.ElementTree(index)


CDATA_ELEMENTS = ("changelog", "description")


def serialise(tree: ET.ElementTree) -> str:
    ET.indent(tree, space="  ")
    xml = ET.tostring(tree.getroot(), encoding="unicode")
    # ReaPack's own indexer emits changelog/description as CDATA. Restore that:
    # the payload is RTF and plain text, and CDATA keeps it readable.
    for tag in CDATA_ELEMENTS:
        xml = re.sub(
            rf"<{tag}>(.*?)</{tag}>",
            lambda m: f"<{tag}><![CDATA[{unescape(m.group(1))}]]></{tag}>",
            xml, flags=re.S,
        )
    return '<?xml version="1.0" encoding="utf-8"?>\n' + xml + "\n"


def unescape(s: str) -> str:
    return (s.replace("&lt;", "<").replace("&gt;", ">")
             .replace("&quot;", '"').replace("&apos;", "'")
             .replace("&amp;", "&"))


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate a ReaPack index for this repository.")
    ap.add_argument("--check", action="store_true",
                    help="validate headers and list packages, write nothing")
    ap.add_argument("-o", "--output", default=os.path.join(ROOT, "index.xml"))
    args = ap.parse_args()

    try:
        packages = collect()
    except HeaderError as err:
        sys.stderr.write(f"error: {err}\n")
        return 1

    if not packages:
        sys.stderr.write("error: no packages found\n")
        return 1

    files = sum(len(p.provides) for p in packages)
    for pkg in sorted(packages, key=lambda p: p.rel):
        extra = len(pkg.provides) - 1
        suffix = f"  (+{extra} file{'s' if extra > 1 else ''})" if extra else ""
        print(f"  {pkg.rel:<40} {pkg.version:<8} {pkg.desc or ''}{suffix}")
    print(f"\n{len(packages)} packages, {files} files, "
          f"{len({p.category for p in packages})} categories")

    if args.check:
        print("check only, index not written")
        return 0

    tree = build(packages)
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(serialise(tree))
    print(f"wrote {os.path.relpath(args.output, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
