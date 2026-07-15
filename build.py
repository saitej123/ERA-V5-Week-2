#!/usr/bin/env python3
"""ERA V5 Week 2 — faithful Markdown multilingual BPE pipeline.

Builds ONE shared 10,000-token vocabulary over the Wikipedia India page in
English, Hindi, Telugu, and Maithili.

This matches the graded setup:
  - wiki-faithful HTML → Markdown corpus (links, tables, refs kept)
  - HuggingFace BPE + NFKC + Metaspace (not ByteLevel)
  - fertility = tokens / faithful_units  (not clipped word samples)
  - languages: en, hi, te, mai  (Maithili, not Tamil)

Usage
-----
    python build.py --fetch    # (re)download faithful Markdown corpus
    python build.py            # train + evaluate + build index.html
    python build.py --all      # fetch then build

Requires: tokenizers regex requests beautifulsoup4 lxml markdownify
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import quote, urljoin

import regex
from tokenizers import Tokenizer
from tokenizers.decoders import Metaspace as MetaspaceDecoder
from tokenizers.models import BPE
from tokenizers.normalizers import NFKC
from tokenizers.pre_tokenizers import Metaspace
from tokenizers.trainers import BpeTrainer

BASE = Path(__file__).resolve().parent
CORPUS = BASE / "corpus"
TOK_PATH = BASE / "tokenizer.json"
WIDGET_TOK_PATH = BASE / "tokenizer.widget.json"
STATS_PATH = BASE / "stats.json"
METRICS_PATH = BASE / "metrics.json"
TEMPLATE_PATH = BASE / "_widget.tpl"
HTML_PATH = BASE / "index.html"

LANGS = ["en", "hi", "te", "mai"]
LANG_NAMES = {
    "en": "English",
    "hi": "Hindi",
    "te": "Telugu",
    "mai": "Maithili",
}
WEIGHTS = {"en": 3, "hi": 4, "te": 4, "mai": 2}
VOCAB_SIZE = 10000
FAITHFUL_UNIT_RE = regex.compile(r"[\p{L}\p{M}\p{N}]+|[^\s\p{L}\p{M}\p{N}]")

PAGES = {
    "en": ("English", "India"),
    "hi": ("Hindi", "भारत"),
    "te": ("Telugu", "భారతదేశం"),
    "mai": ("Maithili", "भारत"),
}
USER_AGENT = "ERA-V5-Week-2-tokenizer/1.0 (educational)"


# --------------------------------------------------------------------------- #
# Faithful units + corpus                                                     #
# --------------------------------------------------------------------------- #
def faithful_units(text: str) -> int:
    return len(FAITHFUL_UNIT_RE.findall(text))


def load_corpus() -> dict[str, str]:
    texts = {}
    for code in LANGS:
        path = CORPUS / f"{code}.faithful.txt"
        if not path.exists():
            sys.exit(f"Missing {path}. Run: python build.py --fetch")
        texts[code] = path.read_text(encoding="utf-8")
    return texts


def fetch_corpus() -> None:
    """Fetch Wikipedia REST HTML and convert to wiki-faithful Markdown."""
    try:
        import requests
        from bs4 import BeautifulSoup
        from markdownify import markdownify as md
    except ImportError as exc:
        sys.exit(
            "Missing fetch deps. Install with:\n"
            "  pip install requests beautifulsoup4 lxml markdownify\n"
            f"({exc})"
        )

    CORPUS.mkdir(parents=True, exist_ok=True)

    def get(url: str):
        return requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=(8, 30))

    def absolutize_links(soup: BeautifulSoup, lang: str) -> None:
        base = f"https://{lang}.wikipedia.org/wiki/"
        for tag in soup.find_all(["a", "img", "source"]):
            attr = "href" if tag.name == "a" else "src"
            value = tag.get(attr)
            if not value:
                continue
            if value.startswith("//"):
                tag[attr] = "https:" + value
            elif value.startswith("./"):
                tag[attr] = urljoin(base, value[2:])
            elif value.startswith("/"):
                tag[attr] = urljoin(f"https://{lang}.wikipedia.org", value)

    def strip_only_technical_noise(node, soup) -> None:
        for tag in node(["script", "style", "meta"]):
            tag.decompose()
        for tag in node.find_all("link"):
            rel = " ".join(tag.get("rel") or [])
            href = tag.get("href") or ""
            if "mw:PageProp/Category" in rel and href:
                tag.replace_with(soup.new_string(f"\nCategory: {href}\n"))
            else:
                tag.decompose()

    def normalize_markdown(markdown: str) -> str:
        markdown = markdown.replace("\xa0", " ")
        markdown = re.sub(r"\n{4,}", "\n\n\n", markdown)
        markdown = re.sub(r"[ \t]+\n", "\n", markdown)
        return markdown.strip() + "\n"

    for lang, (name, title) in PAGES.items():
        url = f"https://{lang}.wikipedia.org/api/rest_v1/page/html/{quote(title)}"
        res = get(url)
        res.raise_for_status()
        raw_path = CORPUS / f"{lang}.raw.html"
        raw_path.write_text(res.text, encoding="utf-8")

        soup = BeautifulSoup(res.text, "lxml")
        body = soup.find("body") or soup
        strip_only_technical_noise(body, soup)
        absolutize_links(body, lang)
        markdown = normalize_markdown(
            md(str(body), heading_style="ATX", bullets="-", strip=["span"])
        )

        (CORPUS / f"{lang}.faithful.md").write_text(markdown, encoding="utf-8")
        (CORPUS / f"{lang}.faithful.txt").write_text(markdown, encoding="utf-8")
        meta = {
            "lang": lang,
            "title": title,
            "source_url": url,
            "variant": "wiki_faithful_markdown",
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "chars": len(markdown),
            "faithful_units": faithful_units(markdown),
            "unit_policy": (
                "Counts each contiguous Unicode letter/mark/number run as one unit "
                "and each visible non-space punctuation/symbol character as one unit."
            ),
        }
        (CORPUS / f"{lang}.meta.json").write_text(
            json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"  {lang} {name}: {meta['faithful_units']} faithful units")
        time.sleep(0.2)


# --------------------------------------------------------------------------- #
# Train                                                                       #
# --------------------------------------------------------------------------- #
def make_tokenizer() -> Tokenizer:
    tokenizer = Tokenizer(BPE(unk_token="[UNK]"))
    tokenizer.normalizer = NFKC()
    tokenizer.pre_tokenizer = Metaspace(replacement="▁", prepend_scheme="never")
    tokenizer.decoder = MetaspaceDecoder(replacement="▁", prepend_scheme="never")
    return tokenizer


def train(texts: dict[str, str]) -> tuple[Tokenizer, dict]:
    units = {code: faithful_units(text) for code, text in texts.items()}

    with tempfile.TemporaryDirectory() as tmp:
        files: list[str] = []
        tmpdir = Path(tmp)
        for code, text in texts.items():
            path = tmpdir / f"{code}.txt"
            path.write_text(text, encoding="utf-8")
            files.extend([str(path)] * WEIGHTS[code])

        tokenizer = make_tokenizer()
        trainer = BpeTrainer(
            vocab_size=VOCAB_SIZE,
            min_frequency=1,
            special_tokens=["[UNK]"],
        )
        tokenizer.train(files, trainer)

    token_counts = {code: len(tokenizer.encode(text).ids) for code, text in texts.items()}
    ratios = {code: token_counts[code] / units[code] for code in LANGS}
    spread = max(ratios.values()) - min(ratios.values())
    score = 1000.0 / spread
    hindi_penalty = math.exp(max(0.0, ratios["hi"] / 1.2 - 1.0))

    metrics = {
        "variant": "wiki_faithful_markdown",
        "languages": LANG_NAMES,
        "weights": WEIGHTS,
        "vocab_size": tokenizer.get_vocab_size(),
        "faithful_units": units,
        "unit_policy": (
            "Counts each contiguous Unicode letter/mark/number run as one unit "
            "and each visible non-space punctuation/symbol character as one unit."
        ),
        "token_counts": token_counts,
        "ratios": ratios,
        "spread": spread,
        "score": score,
        "hindi_exp1_penalty_factor": hindi_penalty,
        "hindi_exp1_adjusted_score": score / hindi_penalty,
    }
    return tokenizer, metrics


def compute_stats(metrics: dict) -> dict:
    """Widget-friendly stats derived from training metrics."""
    per_lang = {}
    for code in LANGS:
        tokens = metrics["token_counts"][code]
        units = metrics["faithful_units"][code]
        x = metrics["ratios"][code]
        per_lang[code] = {
            "name": LANG_NAMES[code],
            "faithful_units": units,
            "tokens": tokens,
            "X": round(x, 6),
            "X_inverse": round(1.0 / x, 6) if x else 0.0,
        }

    ordered = sorted(
        ((c, per_lang[c]["X"]) for c in LANGS), key=lambda kv: kv[1]
    )
    x_min_lang, x_min = ordered[0]
    x_max_lang, x_max = ordered[-1]
    spread = x_max - x_min
    score = 1000.0 / spread if spread > 0 else float("inf")

    return {
        "vocab_size": metrics["vocab_size"],
        "variant": "wiki_faithful_markdown",
        "weights": WEIGHTS,
        "ratio_definition": (
            "X = tokens / faithful_units on the full wiki-faithful Markdown page "
            "(letter/mark/number run OR one visible punctuation/symbol)"
        ),
        "per_language": per_lang,
        "sorted_ascending": [
            {"lang": c, "name": LANG_NAMES[c], "X": round(x, 6)} for c, x in ordered
        ],
        "X_min": {
            "lang": x_min_lang,
            "name": LANG_NAMES[x_min_lang],
            "value": round(x_min, 6),
        },
        "X_max": {
            "lang": x_max_lang,
            "name": LANG_NAMES[x_max_lang],
            "value": round(x_max, 6),
        },
        "spread": round(spread, 6),
        "score": round(score, 2),
        "hindi_penalty_factor": round(metrics["hindi_exp1_penalty_factor"], 6),
        "hindi_adjusted_score": round(metrics["hindi_exp1_adjusted_score"], 2),
        "all_under_1_2": all(v <= 1.2 for v in (per_lang[c]["X"] for c in LANGS)),
        "approach": "hf-bpe-metaspace-weighted",
    }


def export_widget_tokenizer(tokenizer: Tokenizer) -> dict:
    """Flatten HF tokenizer.json into a JS-friendly Metaspace BPE payload."""
    raw = json.loads(tokenizer.to_str())
    model = raw["model"]
    vocab_map = model["vocab"]
    # id-ordered list for the widget browser
    size = max(vocab_map.values()) + 1
    vocab_list = [""] * size
    for tok, idx in vocab_map.items():
        vocab_list[idx] = tok
    merges = model["merges"]
    # ensure list-of-pairs form
    norm_merges = []
    for m in merges:
        if isinstance(m, list):
            norm_merges.append(m)
        else:
            a, b = m.split(" ", 1)
            norm_merges.append([a, b])
    return {
        "format": "metaspace_bpe",
        "vocab_size": size,
        "unk_token": "[UNK]",
        "replacement": "▁",
        "prepend_scheme": "never",
        "normalizer": "NFKC",
        "vocab": vocab_list,
        "merges": norm_merges,
        "languages": LANGS,
        "weights": WEIGHTS,
        "approach": "hf-bpe-metaspace-weighted",
    }


def build_widget(widget_tok: dict, stats: dict) -> float:
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    html = template.replace(
        "/*__TOKENIZER_JSON__*/",
        json.dumps(widget_tok, ensure_ascii=False, separators=(",", ":")),
    )
    html = html.replace(
        "/*__STATS_JSON__*/",
        json.dumps(stats, ensure_ascii=False, separators=(",", ":")),
    )
    HTML_PATH.write_text(html, encoding="utf-8")
    return HTML_PATH.stat().st_size / 1024


def build_all() -> None:
    texts = load_corpus()
    print("Corpus faithful units:", {c: faithful_units(t) for c, t in texts.items()})
    print(
        f"Training HF BPE (vocab={VOCAB_SIZE}, weights={WEIGHTS}, "
        "normalizer=NFKC, pretok=Metaspace) ..."
    )
    tokenizer, metrics = train(texts)
    tokenizer.save(str(TOK_PATH))
    METRICS_PATH.write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    stats = compute_stats(metrics)
    STATS_PATH.write_text(
        json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    widget_tok = export_widget_tokenizer(tokenizer)
    WIDGET_TOK_PATH.write_text(
        json.dumps(widget_tok, ensure_ascii=False), encoding="utf-8"
    )
    kb = build_widget(widget_tok, stats)

    # Round-trip sanity check (non-whitespace characters must survive)
    sample = "India's population is 1,428,627,663."
    enc = tokenizer.encode(sample)
    dec = tokenizer.decode(enc.ids)
    nw = lambda s: regex.sub(r"\s+", "", s)
    assert nw(sample) == nw(dec), f"round-trip failed: {sample!r} -> {dec!r}"

    print("\n=== Result ===")
    for row in stats["sorted_ascending"]:
        p = stats["per_language"][row["lang"]]
        print(
            f"  {row['name']:8s}  tokens={p['tokens']:7d}  "
            f"units={p['faithful_units']:7d}  X={row['X']:.6f}"
        )
    print(
        f"  spread={stats['spread']:.6f}  score={stats['score']:.2f}  "
        f"all<=1.2={stats['all_under_1_2']}  "
        f"hindi_adj={stats['hindi_adjusted_score']:.2f}"
    )
    print(f"  wrote tokenizer.json, metrics.json, stats.json, index.html ({kb:.0f} KB)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--fetch",
        action="store_true",
        help="download wiki-faithful Markdown corpus (en/hi/te/mai)",
    )
    ap.add_argument("--all", action="store_true", help="fetch then build")
    args = ap.parse_args()
    if args.fetch or args.all:
        print("Fetching wiki-faithful Markdown corpus ...")
        fetch_corpus()
    if args.fetch and not args.all:
        return 0
    build_all()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
