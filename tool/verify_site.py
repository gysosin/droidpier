#!/usr/bin/env python3
"""Verify the public landing page, search metadata, and local assets."""
from html.parser import HTMLParser
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
EXPECTED_ORIGIN = "https://gysosin.github.io/droidpier/"


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.meta = {}
        self.canonical = None
        self.title = ""
        self._in_title = False
        self.json_ld = []
        self._json_chunks = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag in {"a", "link"} and values.get("href"):
            self.links.append(values["href"])
        if tag in {"img", "script"} and values.get("src"):
            self.links.append(values["src"])
        if tag == "meta":
            key = values.get("name") or values.get("property")
            if key:
                self.meta[key] = values.get("content", "")
        if tag == "link" and values.get("rel") == "canonical":
            self.canonical = values.get("href")
        if tag == "title":
            self._in_title = True
        if tag == "script" and values.get("type") == "application/ld+json":
            self._json_chunks = []

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        if tag == "script" and self._json_chunks is not None:
            self.json_ld.append("".join(self._json_chunks))
            self._json_chunks = None

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if self._json_chunks is not None:
            self._json_chunks.append(data)


def jpeg_size(path):
    data = path.read_bytes()
    index = 2
    while index + 8 < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        index += 2
        if marker in {0xD8, 0xD9}:
            continue
        length = int.from_bytes(data[index:index + 2], "big")
        if marker in range(0xC0, 0xC4):
            return (
                int.from_bytes(data[index + 5:index + 7], "big"),
                int.from_bytes(data[index + 3:index + 5], "big"),
            )
        index += length
    raise ValueError(f"Cannot read JPEG dimensions: {path}")


def main():
    errors = []
    canonical_urls = set()
    for html_path in sorted(SITE.rglob("index.html")):
        parser = SiteParser()
        parser.feed(html_path.read_text())
        relative = html_path.relative_to(SITE)
        prefix = f"{relative}: "

        if not parser.canonical or not parser.canonical.startswith(EXPECTED_ORIGIN):
            errors.append(prefix + "canonical URL is missing or incorrect")
        elif parser.canonical in canonical_urls:
            errors.append(prefix + "canonical URL is duplicated")
        else:
            canonical_urls.add(parser.canonical)
        if "DroidPier" not in parser.title:
            errors.append(prefix + "title lacks the product name")
        description = parser.meta.get("description", "")
        if not 120 <= len(description) <= 170:
            errors.append(prefix + "meta description should be between 120 and 170 characters")
        for key in ("og:title", "og:description", "og:url", "og:image", "twitter:card"):
            if not parser.meta.get(key):
                errors.append(prefix + f"missing social metadata: {key}")
        if not parser.json_ld:
            errors.append(prefix + "missing structured data")
        else:
            try:
                json.loads(parser.json_ld[0])
            except json.JSONDecodeError as exc:
                errors.append(prefix + f"invalid JSON-LD: {exc}")

        for target in parser.links:
            if re.match(r"(?:https?:|mailto:|#)", target):
                continue
            local = (html_path.parent / target.split("?", 1)[0].split("#", 1)[0]).resolve()
            if local.is_dir():
                local = local / "index.html"
            if (not local.is_file() or
                    (local != SITE.resolve() and SITE.resolve() not in local.parents)):
                errors.append(prefix + f"missing or unsafe local site asset: {target}")

    if EXPECTED_ORIGIN not in canonical_urls:
        errors.append("Landing page canonical URL is missing")

    public_text = "\n".join(
        path.read_text()
        for path in SITE.rglob("*")
        if path.is_file() and path.suffix in {".html", ".css", ".js", ".xml"}
    )
    if any(mark in public_text for mark in ("\u2013", "\u2014")):
        errors.append("Site contains an en dash or em dash")
    for forbidden in ("OpenDex", "Open DEX", "CLAUDE.md", "AGENTS.md", ".agents"):
        if forbidden.lower() in public_text.lower():
            errors.append(f"Private or old project term appears on site: {forbidden}")

    preview = SITE / "assets/social-preview.jpg"
    if preview.stat().st_size >= 1024 * 1024:
        errors.append("Social preview must be smaller than 1 MB")
    if jpeg_size(preview) != (1280, 640):
        errors.append("Social preview must be exactly 1280 by 640 pixels")
    if EXPECTED_ORIGIN not in (SITE / "robots.txt").read_text():
        errors.append("robots.txt does not advertise the canonical sitemap")
    sitemap = (SITE / "sitemap.xml").read_text()
    for canonical in canonical_urls:
        if canonical not in sitemap:
            errors.append(f"sitemap.xml does not contain canonical page: {canonical}")

    if errors:
        raise SystemExit("\n".join(errors))
    print("Landing page, metadata, structured data and local asset checks passed.")


if __name__ == "__main__":
    main()
