"""Multilingual byte-level BPE tokenizer -- full pipeline in one file.

Builds ONE shared 10,000-token vocabulary over the Wikipedia "India" page in
English, Hindi, Telugu and Tamil so that every language's tokens/word ratio is
<= 1.2 and the spread X_max - X_min (the score driver, 1000/spread) is tiny.

Usage
-----
    python3 build.py            # allocate + stats + build index.html (needs corpus/)
    python3 build.py --fetch    # (re)download the India page per language first
    python3 build.py --all      # fetch + build

Outputs: corpus/*.txt (with --fetch), tokenizer.json, stats.json, index.html.
Only index.html needs to be deployed (drag onto Netlify Drop).
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from collections import Counter

try:
    import regex as _re  # supports \p{L} \p{M} \p{N}
    HAVE_REGEX = True
except ImportError:  # pragma: no cover
    _re = re
    HAVE_REGEX = False

BASE = os.path.dirname(os.path.abspath(__file__))
CORPUS_DIR = os.path.join(BASE, "corpus")
TOK_PATH = os.path.join(BASE, "tokenizer.json")
STATS_PATH = os.path.join(BASE, "stats.json")
TEMPLATE_PATH = os.path.join(BASE, "_widget.tpl")
HTML_PATH = os.path.join(BASE, "index.html")

VOCAB_SIZE = 10000
BASE_TOKENS = 256
MERGE_BUDGET = VOCAB_SIZE - BASE_TOKENS  # 9744
LANGS = ["en", "hi", "te", "ta"]
LANG_NAMES = {"en": "English", "hi": "Hindi", "te": "Telugu", "ta": "Tamil"}

# Equal word sample per language: the ratio is measured on the same number of
# words for each language so the four X values are comparable, and small enough
# that all four fit under one shared 10k vocab (see water-fill below).
SAMPLE_WORDS = 1500

STEP = 5  # water-fill granularity (merges handed out per round)


# --------------------------------------------------------------------------- #
# Pre-tokenization                                                            #
# --------------------------------------------------------------------------- #
# Two departures from vanilla GPT-2, both lowering tokens/word honestly:
#   1. Indic combining marks: match [\p{L}\p{M}]+ so a base consonant plus its
#      dependent vowel signs / viramas (categories Mn/Mc) stay in ONE chunk.
#      A bare \p{L}+ splits at every mark, shattering words before BPE runs.
#   2. Attached punctuation: a word/number absorbs surrounding brackets, commas
#      and periods, so "India," or "(1947)" is ~1 token instead of 2-3.
_LEAD = r"[(\[{\"'\u2018\u201c\u00a1\u00bf]*"
_TRAIL = r"[.,;:!?)\]}%'\"\u2019\u201d\u2026]*"
if HAVE_REGEX:
    PAT = _re.compile(
        r"""'s|'t|'re|'ve|'m|'ll|'d"""
        r"""| ?""" + _LEAD + r"""[\p{L}\p{M}]+""" + _TRAIL +
        r"""| ?\p{N}[\p{N}.,:/]*""" + _TRAIL +
        r"""| ?[^\s\p{L}\p{M}\p{N}]+|\s+""",
        _re.UNICODE,
    )
else:
    PAT = _re.compile(
        r"""'s|'t|'re|'ve|'m|'ll|'d| ?[^\s\d\W]+| ?\d+| ?[^\s\w]+|\s+""",
        _re.UNICODE,
    )


def bytes_to_unicode():
    """GPT-2's reversible byte<->unicode mapping (printable, JSON-safe)."""
    bs = (
        list(range(ord("!"), ord("~") + 1))
        + list(range(ord("\u00a1"), ord("\u00ac") + 1))
        + list(range(ord("\u00ae"), ord("\u00ff") + 1))
    )
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b)
            cs.append(256 + n)
            n += 1
    return {b: chr(c) for b, c in zip(bs, cs)}


BYTE_ENCODER = bytes_to_unicode()
BYTE_DECODER = {v: k for k, v in BYTE_ENCODER.items()}


def word_sample(text, n_words=SAMPLE_WORDS):
    return " ".join(text.split()[:n_words])


def load_sample_texts(n_words=SAMPLE_WORDS):
    """Equal n_words-word sample of each language's India page."""
    raw = {}
    for lang in LANGS:
        with open(os.path.join(CORPUS_DIR, f"{lang}.txt"), "r", encoding="utf-8") as fh:
            raw[lang] = word_sample(fh.read(), n_words)
    return raw


def pre_tokenize(text):
    wf = Counter()
    for chunk in PAT.findall(text):
        symbols = tuple(BYTE_ENCODER[x] for x in chunk.encode("utf-8"))
        if symbols:
            wf[symbols] += 1
    return wf


# --------------------------------------------------------------------------- #
# BPE training (fast incremental merges with a lazy max-heap)                 #
# --------------------------------------------------------------------------- #
def learn_bpe(word_freq, vocab_size=VOCAB_SIZE):
    """Learn merges from a symbol-tuple frequency table.

    Maintains pair->freq and pair->{word: count} incrementally so each merge only
    touches affected words, and uses a lazy-deletion max-heap to pick the best
    pair in ~O(log N). Returns (vocab, merges).
    """
    import heapq

    words, freqs, word_index = [], [], {}
    for syms, f in word_freq.items():
        if f <= 0 or len(syms) < 1:
            continue
        key = tuple(syms)
        wid = word_index.get(key)
        if wid is None:
            word_index[key] = len(words)
            words.append(list(syms))
            freqs.append(f)
        else:
            freqs[wid] += f

    pair_freq = Counter()
    pair_word_count = {}
    heap = []
    seen_heap = set()

    def add_pair(a, b, wid):
        p = (a, b)
        d = pair_word_count.get(p)
        if d is None:
            d = {}
            pair_word_count[p] = d
        prev = d.get(wid, 0)
        d[wid] = prev + 1
        if prev == 0:
            pair_freq[p] += freqs[wid]

    def remove_pair(a, b, wid):
        p = (a, b)
        d = pair_word_count.get(p)
        if d is None:
            return
        prev = d.get(wid, 0)
        if prev <= 0:
            return
        d[wid] = prev - 1
        if prev - 1 == 0:
            del d[wid]
            pair_freq[p] -= freqs[wid]
            if not d:
                del pair_word_count[p]
                pair_freq.pop(p, None)

    def push_pair(p):
        if p in seen_heap:
            return
        seen_heap.add(p)
        heapq.heappush(heap, (-pair_freq[p], p))

    for wid, syms in enumerate(words):
        for i in range(len(syms) - 1):
            add_pair(syms[i], syms[i + 1], wid)
    for p, f in pair_freq.items():
        if f > 0:
            seen_heap.add(p)
            heapq.heappush(heap, (-f, p))

    vocab = [BYTE_ENCODER[b] for b in range(256)]
    vocab_set = set(vocab)
    merges = []
    num_merges = vocab_size - len(vocab)

    for _ in range(num_merges):
        best_pair, best_freq = None, 0
        while heap:
            neg_f, p = heapq.heappop(heap)
            seen_heap.discard(p)
            cur = pair_freq.get(p, 0)
            if cur <= 0:
                continue
            if -neg_f == cur:
                best_pair, best_freq = p, cur
                break
            seen_heap.add(p)
            heapq.heappush(heap, (-cur, p))
        if best_pair is None or best_freq < 1:
            break

        a, b = best_pair
        new_symbol = a + b
        affected = list(pair_word_count.get(best_pair, {}).keys())
        for wid in affected:
            syms = words[wid]
            for i in range(len(syms) - 1):
                remove_pair(syms[i], syms[i + 1], wid)
        for wid in affected:
            syms = words[wid]
            new_syms, i = [], 0
            while i < len(syms):
                if i < len(syms) - 1 and syms[i] == a and syms[i + 1] == b:
                    new_syms.append(new_symbol)
                    i += 2
                else:
                    new_syms.append(syms[i])
                    i += 1
            words[wid] = new_syms
            for i in range(len(new_syms) - 1):
                add_pair(new_syms[i], new_syms[i + 1], wid)
        for wid in affected:
            if freqs[wid] <= 0:
                continue
            syms = words[wid]
            for i in range(len(syms) - 1):
                push_pair((syms[i], syms[i + 1]))

        merges.append([a, b])
        if new_symbol not in vocab_set:
            vocab.append(new_symbol)
            vocab_set.add(new_symbol)

    return vocab, merges


def encode(text, ranks):
    """Encode text to a list of token strings using merge ranks."""
    tokens = []
    for chunk in PAT.findall(text):
        symbols = [BYTE_ENCODER[x] for x in chunk.encode("utf-8")]
        if len(symbols) >= 2:
            while True:
                best_rank, best_i = None, -1
                for i in range(len(symbols) - 1):
                    r = ranks.get((symbols[i], symbols[i + 1]))
                    if r is not None and (best_rank is None or r < best_rank):
                        best_rank, best_i = r, i
                if best_i == -1:
                    break
                symbols[best_i:best_i + 2] = [symbols[best_i] + symbols[best_i + 1]]
        tokens.extend(symbols)
    return tokens


def x_ratio(text, ranks):
    words = len(text.split())
    return len(encode(text, ranks)) / words if words else 0.0


# --------------------------------------------------------------------------- #
# Water-fill allocation of the shared merge budget                           #
# --------------------------------------------------------------------------- #
# The four scripts barely share merges, so four independent full vocabularies
# would need ~21k merges but we only have 9,744. We learn each language's merges
# independently, then repeatedly hand the next block of merges to whichever
# language currently has the WORST (highest) tokens/word. All four ratios
# descend together and converge -> X_max - X_min shrinks while every X stays low.
def allocate(raw):
    words = {l: len(raw[l].split()) for l in LANGS}
    merges = {}
    for l in LANGS:
        _, merges[l] = learn_bpe(pre_tokenize(raw[l]), VOCAB_SIZE)

    # Build X-vs-merges curve per language.
    curves = {}
    for l in LANGS:
        pts, n, total = [], 0, len(merges[l])
        while n <= total:
            ranks = {(a, b): i for i, (a, b) in enumerate(merges[l][:n])}
            pts.append((n, len(encode(raw[l], ranks)) / words[l]))
            if n == total:
                break
            n = min(total, n + STEP)
        curves[l] = pts

    idx = {l: 0 for l in LANGS}
    x_now = lambda l: curves[l][idx[l]][1]
    n_now = lambda l: curves[l][idx[l]][0]
    used = 0
    while True:
        cand = [l for l in LANGS if idx[l] < len(curves[l]) - 1]
        if not cand:
            break
        worst = max(cand, key=x_now)
        cost = curves[worst][idx[worst] + 1][0] - n_now(worst)
        if used + cost > MERGE_BUDGET:
            break
        idx[worst] += 1
        used += cost

    alloc = {l: n_now(l) for l in LANGS}
    return merges, alloc, used


def build_shared_vocab(merges, alloc):
    """Assemble one 10k vocab. English merges go FIRST (Latin appears in every
    page, so its greedy path is the most order-sensitive), then the mutually
    disjoint Indic scripts; duplicate pairs kept once at their earliest slot."""
    vocab = [BYTE_ENCODER[b] for b in range(256)]
    vocab_set = set(vocab)
    seen, shared = set(), []

    def add(a, b):
        if (a, b) in seen:
            return
        seen.add((a, b))
        shared.append([a, b])
        s = a + b
        if s not in vocab_set:
            vocab.append(s)
            vocab_set.add(s)

    for a, b in merges["en"][:alloc["en"]]:
        add(a, b)
    rest = [l for l in LANGS if l != "en"]
    max_len = max((alloc[l] for l in rest), default=0)
    for r in range(max_len):
        for l in rest:
            if r < alloc[l]:
                a, b = merges[l][r]
                add(a, b)

    reserved = 0
    while len(vocab) < VOCAB_SIZE:
        t = f"<|reserved_{reserved}|>"
        if t not in vocab_set:
            vocab.append(t)
            vocab_set.add(t)
        reserved += 1

    return {
        "vocab_size": len(vocab),
        "learned_tokens": len(vocab) - reserved,
        "reserved_tokens": reserved,
        "byte_to_unicode": {str(b): BYTE_ENCODER[b] for b in range(256)},
        "vocab": vocab,
        "merges": shared,
        "pattern": PAT.pattern,
        "languages": LANGS,
        "allocation": alloc,
        "sample_words": SAMPLE_WORDS,
        "approach": "partitioned-waterfill",
    }


# --------------------------------------------------------------------------- #
# Stats                                                                       #
# --------------------------------------------------------------------------- #
def compute_stats(tok, raw):
    ranks = {(a, b): i for i, (a, b) in enumerate(tok["merges"])}
    per_lang = {}
    for lang in LANGS:
        text = raw[lang]
        toks = encode(text, ranks)
        words = len(text.split())
        n = len(toks)
        per_lang[lang] = {
            "name": LANG_NAMES[lang],
            "words": words,
            "tokens": n,
            "X": round(n / words, 4) if words else 0.0,
            "X_inverse": round(words / n, 4) if n else 0.0,
        }

    xs = {l: per_lang[l]["X"] for l in per_lang}
    ordered = sorted(xs.items(), key=lambda kv: kv[1])
    x_min_lang, x_min = ordered[0]
    x_max_lang, x_max = ordered[-1]
    spread = x_max - x_min
    score = (1000.0 / spread) if spread > 0 else float("inf")

    return {
        "vocab_size": tok["vocab_size"],
        "learned_tokens": tok["learned_tokens"],
        "reserved_tokens": tok["reserved_tokens"],
        "sample_words": tok["sample_words"],
        "allocation": tok["allocation"],
        "approach": tok["approach"],
        "ratio_definition": "X = tokens / words on an equal per-language word sample (lower is better; target <= 1.2)",
        "per_language": per_lang,
        "sorted_ascending": [{"lang": l, "name": LANG_NAMES[l], "X": x} for l, x in ordered],
        "X_min": {"lang": x_min_lang, "name": LANG_NAMES[x_min_lang], "value": round(x_min, 4)},
        "X_max": {"lang": x_max_lang, "name": LANG_NAMES[x_max_lang], "value": round(x_max, 4)},
        "spread": round(spread, 4),
        "score": round(score, 2),
        "all_under_1_2": all(v <= 1.2 for v in xs.values()),
    }


def build_widget(tok, stats):
    with open(TEMPLATE_PATH, "r", encoding="utf-8") as fh:
        template = fh.read()
    html = template.replace("/*__TOKENIZER_JSON__*/", json.dumps(tok, ensure_ascii=False, separators=(",", ":")))
    html = html.replace("/*__STATS_JSON__*/", json.dumps(stats, ensure_ascii=False, separators=(",", ":")))
    with open(HTML_PATH, "w", encoding="utf-8") as fh:
        fh.write(html)
    return os.path.getsize(HTML_PATH) / 1024


# --------------------------------------------------------------------------- #
# Fetch the Wikipedia "India" page per language (run with --fetch)           #
# --------------------------------------------------------------------------- #
_WIKI_TITLES = {"en": "India", "hi": "भारत", "te": "భారతదేశం", "ta": "இந்தியா"}
_USER_AGENT = "BPE-Tokenizer-Assignment/1.0 (educational; contact: student@example.com)"
_BACKMATTER = {
    "en": ["See also", "Notes", "References", "Bibliography", "Further reading", "External links"],
    "hi": ["इन्हें भी देखें", "सन्दर्भ", "टिप्पणी सूची", "बाहरी कड़ियाँ", "ग्रन्थसूची"],
    "te": ["ఇవికూడా చూడండి", "చిత్రమాలిక", "గమనికలు", "మూలాలు", "ఉపయుక్త గ్రంథాలు", "వెలుపలి లంకెలు"],
    "ta": ["இவற்றையும் பார்க்கவும்", "துணை நூல்கள்", "குறிப்புகள்", "மேற்கோள்கள்", "நூற்பட்டியல்", "வெளி இணைப்புகள்"],
}


def _http_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8")


def _strip_backmatter(lang, text):
    cut = len(text)
    for heading in _BACKMATTER.get(lang, []):
        m = re.search(r"^==+\s*" + re.escape(heading) + r"\s*==+\s*$", text, re.MULTILINE)
        if m and m.start() < cut:
            cut = m.start()
    return text[:cut].strip()


def _resolve_titles():
    titles = dict(_WIKI_TITLES)
    try:
        params = {"action": "query", "prop": "langlinks", "titles": "India",
                  "lllimit": "500", "format": "json"}
        data = json.loads(_http_get("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)))
        for page in data["query"]["pages"].values():
            for ll in page.get("langlinks", []):
                if ll.get("lang") in titles and ll.get("lang") != "en":
                    titles[ll["lang"]] = ll.get("*", titles[ll["lang"]])
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] langlinks failed, using fallbacks: {exc}")
    return titles


def fetch_corpus():
    os.makedirs(CORPUS_DIR, exist_ok=True)
    titles = _resolve_titles()
    print("Resolved India-page titles:", titles)
    for lang in LANGS:
        params = {"action": "query", "prop": "extracts", "explaintext": "1",
                  "titles": titles[lang], "format": "json", "redirects": "1"}
        url = f"https://{lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
        text = ""
        try:
            data = json.loads(_http_get(url))
            for page in data["query"]["pages"].values():
                if page.get("extract", "").strip():
                    text = page["extract"]
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] {lang} fetch failed: {exc}")
        text = _strip_backmatter(lang, text)
        path = os.path.join(CORPUS_DIR, f"{lang}.txt")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"  {lang}: {len(text.split())} words -> {path}")
        time.sleep(0.25)


# --------------------------------------------------------------------------- #
# Pipeline                                                                    #
# --------------------------------------------------------------------------- #
def build_all():
    if not all(os.path.exists(os.path.join(CORPUS_DIR, f"{l}.txt")) for l in LANGS):
        sys.exit("corpus/ is missing. Run: python3 build.py --fetch")

    raw = load_sample_texts()
    print(f"Sample words per language: { {l: len(raw[l].split()) for l in LANGS} }")

    print("Learning per-language merges + water-filling the shared budget ...")
    merges, alloc, used = allocate(raw)
    print(f"  allocation={alloc}  budget used {used}/{MERGE_BUDGET}")

    tok = build_shared_vocab(merges, alloc)
    with open(TOK_PATH, "w", encoding="utf-8") as fh:
        json.dump(tok, fh, ensure_ascii=False)

    stats = compute_stats(tok, raw)
    with open(STATS_PATH, "w", encoding="utf-8") as fh:
        json.dump(stats, fh, ensure_ascii=False, indent=2)

    kb = build_widget(tok, stats)
    print("\n=== Result ===")
    for r in stats["sorted_ascending"]:
        print(f"  {r['name']:8s} X={r['X']}")
    print(f"  spread={stats['spread']}  score={stats['score']}  all<=1.2={stats['all_under_1_2']}")
    print(f"  wrote tokenizer.json, stats.json, index.html ({kb:.0f} KB)")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fetch", action="store_true", help="download the India page per language")
    ap.add_argument("--all", action="store_true", help="fetch then build")
    args = ap.parse_args()
    if args.fetch or args.all:
        fetch_corpus()
    if args.fetch and not args.all:
        return
    build_all()


if __name__ == "__main__":
    main()
