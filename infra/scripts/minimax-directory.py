#!/usr/bin/env python3
"""Parse Minimax's public directory of accounting services into SQL.

    minimax-directory.py RS page.html URL   > upsert.sql

Each country's page lists every office as a popup: the name in <strong>, the
address after it, a website button, and a map pin whose description is the
office's email. The website, or failing that the email's own domain, is the
company's domain; an office reachable only through a free mailbox has no
domain to research and is left out (0029_minimax_directory.sql has the counts).
"""
import html
import json
import re
import sys
from urllib.parse import urlparse

# Mailbox providers, not companies: an office at gmail.com is not gmail.com.
FREEMAIL = re.compile(
    r'(^|\.)(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|me|aol|gmx|'
    r'mail|yandex|proton|protonmail|'
    r'siol|amis|t-2|telemach|arnes|guest\.arnes|volja|kabelnet|'
    r't-com|net|inet|optinet|htnet|'
    r'eunet|open\.telekom|mts|sbb|ptt|beotel|orion|neobee|yubc|verat|sezampro|rocketmail|beograd)'
    r'\.[a-z.]+$', re.I)
NOT_A_SITE = re.compile(r'(minimax|facebook|instagram|linkedin|google|wixsite|business\.site)', re.I)
ENTRY = re.compile(
    r'<li>\s*<a data-popup="branches-popup"[^>]*href="#([^"]+)">\s*<strong>(.*?)</strong>\s*</a>\s*'
    r'(?:<br>\s*([^<]*))?', re.S)


def domain_of(website, email):
    if website:
        w = website.strip()
        host = urlparse(w if '//' in w else 'http://' + w).hostname or ''
        host = host.lower().strip('.')
        if host.startswith('www.'):
            host = host[4:]
        if re.fullmatch(r'[a-z0-9.-]+\.[a-z]{2,}', host) and not NOT_A_SITE.search(host):
            return host
    if email and '@' in email:
        host = email.strip().split('@')[1].lower().strip('. ')
        if re.fullmatch(r'[a-z0-9.-]+\.[a-z]{2,}', host) and not FREEMAIL.search(host) \
                and not NOT_A_SITE.search(host):
            return host[4:] if host.startswith('www.') else host
    return None


def parse(page):
    seen = {}
    matches = list(ENTRY.finditer(page))
    for i, m in enumerate(matches):
        slug = m.group(1)
        if slug in seen:
            continue
        end = matches[i + 1].start() if i + 1 < len(matches) else m.end() + 6000
        block = page[m.end():end]
        site = re.search(r'branches__link">\s*<a[^>]*href="\s*([^"]+?)\s*"', block)
        # The pin's description is typed by the office: "x@y.example\r\n", "a@b.example ; info@b.example".
        mail = re.search(r'"description":"([^"@\s\\,;]+@[^"\s\\,;]+)', block)
        address = re.sub(r'\s+', ' ', html.unescape(m.group(3) or '')).strip() or None
        city = None
        if address:
            pc = re.search(r'\b\d{4,5}\s+(.+)$', address)
            city = pc.group(1).strip() if pc else None
        website = site.group(1) if site else None
        email = mail.group(1).strip() if mail else None
        seen[slug] = {
            'slug': slug,
            'name': re.sub(r'\s+', ' ', html.unescape(m.group(2))).strip(),
            'website': website,
            'email': email,
            'address': address,
            'city': city,
            'domain': domain_of(website, email),
        }
    return list(seen.values())


def main():
    iso, path, url = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path, encoding='utf-8', errors='replace') as f:
        entries = parse(f.read())
    usable = [e for e in entries if e['domain']]
    print(f'-- {iso}: {len(entries)} offices, {len(usable)} with a domain', file=sys.stderr)
    if len(entries) < 50:
        # The page changed shape, or came back as an error page. Keep the
        # last good snapshot rather than replacing it with nothing.
        sys.exit(f'{iso}: only {len(entries)} offices parsed; snapshot left as it was')
    payload = json.dumps(usable, ensure_ascii=False)
    tag = '$snap$'
    assert tag not in payload
    print(
        "INSERT INTO directory_snapshot (source, country, url, entries, elements, fetched_at)\n"
        f"VALUES ('radar_minimax', '{iso}', {tag}{url}{tag}, {tag}{payload}{tag}::jsonb, {len(usable)}, now())\n"
        "ON CONFLICT (source, country) DO UPDATE SET url = EXCLUDED.url, entries = EXCLUDED.entries,\n"
        "    elements = EXCLUDED.elements, fetched_at = EXCLUDED.fetched_at;"
    )


if __name__ == '__main__':
    main()
