# Multilingual BPE Tokenizer (ERA V5 Week 2)

One shared **10,000-token** HuggingFace BPE vocabulary over the Wikipedia **India** page in **English, Hindi, Telugu, and Maithili**.

**Deliverable:** self-contained [`index.html`](index.html) (tokenizer + stats inlined). Deploy anywhere static.

| Metric | Value |
|--------|-------|
| Self score | **≈ 6,500** |
| Spread (X₄ − X₁) | **≈ 0.154** |
| All languages ≤ 1.2 | ✅ yes |
| Vocab | 10,000 Metaspace BPE |
| Corpus | wiki-faithful Markdown (full page) |

| Language | Tokens | Faithful units | X = tokens/units |
|----------|-------:|---------------:|-----------------:|
| Hindi | ~51k | ~88k | **~0.58** |
| English | ~111k | ~186k | **~0.60** |
| Telugu | ~24k | ~36k | **~0.67** |
| Maithili | ~4k | ~6k | **~0.73** |

---

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install tokenizers regex requests beautifulsoup4 lxml markdownify

python build.py --fetch   # download wiki-faithful Markdown -> corpus/
python build.py           # train + evaluate + build index.html

python -m http.server 8000
# → http://localhost:8000/index.html
```

**Deploy:** drag [`index.html`](index.html) onto [Netlify Drop](https://app.netlify.com/drop).

---

## Scoring (graded)

```
faithful_unit = one contiguous Unicode letter/mark/number run
              OR one visible non-space punctuation/symbol character

X(language) = token_count / faithful_unit_count   on the FULL faithful Markdown page

score = 1000 / (X_max - X_min)
```

Also tracked: Hindi penalty `exp(max(0, X_hi/1.2 - 1))`; when Hindi ≤ 1.2 the factor is 1.

**Faithfulness:** `decode(encode(text))` must keep the same non-whitespace characters (apostrophes, number commas, brackets, URL chars, etc.).

---

## What was wrong in earlier attempts (and fixed)

| Mistake | Why it fails | Fix |
|---------|--------------|-----|
| Tamil instead of Maithili | Wrong assignment language | Use `mai` |
| Clipped ~1,700-word sample + tokens/words | Inflates score; not the graded denominator | Full page + faithful units |
| Stripped back-matter / clean prose only | Graders use wiki-faithful Markdown | Keep links, tables, refs |
| Byte-level BPE | Wastes vocab on UTF-8 bytes for Indic | Metaspace + character BPE |
| Custom water-fill on samples | Not reproducible to the reference metric | HF BPE + language weights |

---

## Training choices

- Model: HuggingFace BPE, vocab 10,000, `min_frequency=1`
- Normalizer: NFKC only
- Pretokenizer / decoder: Metaspace (`▁`, `prepend_scheme=never`)
- Weights: `en×3`, `hi×4`, `te×4`, `mai×2`

---

## Project files

| File | Purpose |
|------|---------|
| **`index.html`** | Widget to deploy |
| `build.py` | Fetch → train → evaluate → build widget |
| `_widget.tpl` | HTML template (JSON inlined) |
| `corpus/*.faithful.txt` | Graded Markdown corpus |
| `tokenizer.json` | HuggingFace tokenizer |
| `metrics.json` / `stats.json` | Saved evaluation |

---

## Widget tabs

| Tab | Content |
|-----|---------|
| **Try Tokenizer** | Fertility cards + live Metaspace encoder |
| **Pipeline** | Faithful Markdown → weighted BPE → score |
| **Score** | X₁…X₄ table and spread |
| **Techniques & Limits** | Correct approach vs invalid shortcuts |
| **Vocabulary** | Searchable 10k tokens + downloads |
