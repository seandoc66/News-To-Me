#!/usr/bin/env python3
"""
Backfill photoCandidate entries for articles that lack them.
Reads the archive JSON, extracts og:image from each article's first source URL,
verifies the image exists and meets minimum size from config, then writes
photoCandidate fields back into the JSON.

Usage:
    python3 scripts/backfill-photo-candidates.py docs/archive/YYYY-MM-DD.json
"""

import json
import re
import sys
import os
import urllib.request
import urllib.error
import ssl
from pathlib import Path

# Minimum image dimensions, read from hermes/config.json so this can't drift
# out of sync with fetch-photos.mjs, which enforces the same numbers.
_repo_root = Path(__file__).resolve().parent.parent
_config = json.loads((_repo_root / "hermes" / "config.json").read_text("utf-8"))
MIN_LONG_EDGE = _config["photos"]["minSourceLongEdge"]
MIN_SHORT_EDGE = _config["photos"]["minSourceShortEdge"]

ssl_ctx = ssl.create_default_context()
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"


def fetch_html(url):
    """Fetch a URL and return the HTML text."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15, context=ssl_ctx) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  ⚠  fetch error for {url}: {e}")
        return None


def extract_og_image(html):
    """Extract the og:image URL from HTML meta tags.

    Meta tags can list attributes in any order (some sites emit
    content='...' property='og:image'), so match each attribute pair
    separately and then look up the pair by name.
    """
    # Collect all key-value pairs from every meta tag
    metas = re.findall(r"<meta\s+[^>]*>", html, re.IGNORECASE)
    for tag in metas:
        attrs = dict(
            re.findall(r'\s([a-z0-9:_-]+)=["\']([^"\']*)["\']', tag, re.IGNORECASE)
        )
        key = attrs.get("property", "").lower() or attrs.get("name", "").lower()
        if key == "og:image" and attrs.get("content"):
            return attrs["content"]
    return None


def extract_og_dimensions(html):
    """Extract og:image:width and og:image:height from HTML (any attr order)."""
    metas = re.findall(r"<meta\s+[^>]*>", html, re.IGNORECASE)
    width = height = None
    for tag in metas:
        attrs = dict(
            re.findall(r'\s([a-z0-9:_-]+)=["\']([^"\']*)["\']', tag, re.IGNORECASE)
        )
        key = attrs.get("property", "").lower()
        if key == "og:image:width" and attrs.get("content", "").isdigit():
            width = int(attrs["content"])
        elif key == "og:image:height" and attrs.get("content", "").isdigit():
            height = int(attrs["content"])
    return (width, height)





def verify_image(url):
    """Check if the image URL is reachable and returns image content."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "image/*"})
    try:
        with urllib.request.urlopen(req, timeout=15, context=ssl_ctx) as resp:
            status = resp.status
            ct = resp.headers.get("Content-Type", "")
            if status == 200 and ct.startswith("image/"):
                return True
            print(f"  ⚠  bad response: HTTP {status}, Content-Type: {ct}")
            return False
    except Exception as e:
        print(f"  ⚠  image verify failed: {e}")
        return False


def has_photo(article):
    """Check if article already has a photo or photoCandidate."""
    if article.get("imageURL") and article["imageURL"].strip():
        return True
    if article.get("photoCandidate") and article["photoCandidate"].get("url"):
        return True
    return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/backfill-photo-candidates.py <archive.json>")
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"✗ Not found: {path}")
        sys.exit(1)

    feed = json.loads(path.read_text("utf-8"))
    articles = feed.get("articles", [])
    total = len(articles)
    added = 0
    skipped = 0
    failed = 0

    for i, article in enumerate(articles):
        aid = article.get("id", f"article[{i}]")

        if has_photo(article):
            print(f"  ✓  {aid}  already has photo")
            skipped += 1
            continue

        sources = article.get("sources", [])
        if not sources:
            print(f"  –  {aid}  no sources to extract from")
            failed += 1
            continue

        source_url = sources[0]["url"]
        print(f"  →  {aid}  fetching {source_url}")

        html = fetch_html(source_url)
        if not html:
            failed += 1
            continue

        og_url = extract_og_image(html)
        if not og_url:
            print(f"  ✗  {aid}  no og:image found in {source_url}")
            # Try second source if first didn't have one
            if len(sources) > 1:
                source_url2 = sources[1]["url"]
                print(f"     → trying second source: {source_url2}")
                html2 = fetch_html(source_url2)
                if html2:
                    og_url = extract_og_image(html2)
            if not og_url:
                failed += 1
                continue

        # Check dimensions from meta tags
        width, height = extract_og_dimensions(html)
        if width and height:
            long_edge = max(width, height)
            short_edge = min(width, height)
            if long_edge < MIN_LONG_EDGE or short_edge < MIN_SHORT_EDGE:
                print(f"  ✗  {aid}  og:image too small: {width}x{height} (need min {MIN_LONG_EDGE}x{MIN_SHORT_EDGE})")
                failed += 1
                continue

        # Verify the image actually loads
        if not verify_image(og_url):
            # Try with a different approach - maybe the URL needs encoding
            print(f"  ✗  {aid}  image URL not reachable: {og_url[:80]}")
            failed += 1
            continue

        article["photoCandidate"] = {
            "url": og_url,
            "description": f"OG image from {sources[0]['name']}",
            "license": "fair-use"
        }
        added += 1
        print(f"  ✓  {aid}  photoCandidate added: {og_url[:80]}...")

    path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n", "utf-8")
    print(f"\n{'='*50}")
    print(f"Total: {total} | Added: {added} | Skipped: {skipped} | Failed: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())