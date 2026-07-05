<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Multilingual BPE Tokenizer</title>
<style>
  :root {
    --background: #ffffff;
    --foreground: #09090b;
    --muted: #71717a;
    --muted-fg: #a1a1aa;
    --border: #e4e4e7;
    --input: #e4e4e7;
    --ring: #18181b;
    --primary: #18181b;
    --primary-fg: #fafafa;
    --secondary: #f4f4f5;
    --secondary-fg: #18181b;
    --accent: #f4f4f5;
    --accent-fg: #18181b;
    --destructive: #ef4444;
    --destructive-bg: #fef2f2;
    --success: #16a34a;
    --success-bg: #f0fdf4;
    --sidebar: #fafafa;
    --sidebar-border: #e4e4e7;
    --radius: 0.5rem;
    --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
    --en: #2563eb;
    --hi: #ea580c;
    --te: #059669;
    --ta: #dc2626;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; }
  body {
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto,
      "Noto Sans", "Noto Sans Devanagari", "Noto Sans Telugu", "Noto Sans Tamil", sans-serif;
    background: var(--background);
    color: var(--foreground);
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
  }

  /* icons */
  .icon { width: 16px; height: 16px; stroke: currentColor; fill: none;
    stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; flex-shrink: 0; }
  .icon-sm { width: 14px; height: 14px; }
  .icon-lg { width: 18px; height: 18px; }

  /* shell */
  .app { display: flex; flex-direction: column; min-height: 100vh; }
  .topbar {
    height: 56px; border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
    padding: 0 1.25rem; background: var(--background); position: sticky; top: 0; z-index: 50;
  }
  .topbar-brand { display: flex; align-items: center; gap: 0.625rem; }
  .topbar-logo {
    width: 32px; height: 32px; border-radius: var(--radius);
    background: var(--primary); color: var(--primary-fg);
    display: flex; align-items: center; justify-content: center;
  }
  .topbar-title { font-size: 0.9375rem; font-weight: 600; letter-spacing: -0.01em; }
  .topbar-sub { font-size: 0.75rem; color: var(--muted); font-weight: 400; }
  .score-badge {
    display: inline-flex; align-items: center; gap: 0.375rem;
    padding: 0.375rem 0.75rem; border-radius: 9999px;
    background: var(--success-bg); border: 1px solid #bbf7d0;
    font-size: 0.8125rem; font-weight: 600; color: var(--success);
  }
  .score-badge b { font-variant-numeric: tabular-nums; }

  .body { display: flex; flex: 1; min-height: 0; }

  /* horizontal tab bar */
  .tabbar {
    display: flex; align-items: center; gap: 0.25rem;
    padding: 0 1.25rem; border-bottom: 1px solid var(--border);
    background: var(--background); position: sticky; top: 56px; z-index: 40;
    overflow-x: auto; scrollbar-width: none;
  }
  .tabbar::-webkit-scrollbar { display: none; }
  .tab-btn {
    display: inline-flex; align-items: center; gap: 0.5rem;
    padding: 0.75rem 0.875rem; border: none; background: none;
    font-size: 0.875rem; font-weight: 500; color: var(--muted);
    cursor: pointer; white-space: nowrap; border-bottom: 2px solid transparent;
    transition: color 0.15s, border-color 0.15s; font-family: inherit;
  }
  .tab-btn:hover { color: var(--foreground); }
  .tab-btn.active { color: var(--foreground); border-bottom-color: var(--primary); }
  .tab-btn.active .icon { stroke: var(--foreground); }

  /* main */
  .main {
    flex: 1; min-width: 0; overflow-y: auto;
    padding: 1.75rem 2rem; background: #fafafa;
  }
  .tab-panel { display: none; animation: fadeIn 0.2s ease; max-width: 920px; }
  .tab-panel.active { display: block; }
  @keyframes fadeIn { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: none; } }

  .page-header { margin-bottom: 1.25rem; }
  .page-header h2 {
    font-size: 1.25rem; font-weight: 600; letter-spacing: -0.02em;
    display: flex; align-items: center; gap: 0.5rem;
  }
  .page-header p { font-size: 0.875rem; color: var(--muted); margin-top: 0.3rem; }

  /* right sidebar */
  .sidebar-right {
    width: 280px; flex-shrink: 0;
    border-left: 1px solid var(--sidebar-border);
    background: var(--sidebar); padding: 1.25rem 1rem;
    overflow-y: auto;
  }
  .sb-card {
    background: var(--background); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 1rem; margin-bottom: 0.875rem;
    box-shadow: var(--shadow-sm);
  }
  .sb-card-title {
    font-size: 0.6875rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.05em; color: var(--muted); margin-bottom: 0.625rem;
    display: flex; align-items: center; gap: 0.375rem;
  }
  .score-big {
    font-size: 2.25rem; font-weight: 700; letter-spacing: -0.03em;
    font-variant-numeric: tabular-nums; line-height: 1;
  }
  .score-formula {
    font-size: 0.75rem; color: var(--muted); margin-top: 0.5rem;
    font-family: ui-monospace, "SF Mono", Menlo, monospace; line-height: 1.6;
  }
  .x-list { display: flex; flex-direction: column; gap: 0.5rem; }
  .x-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 0.5rem 0.625rem; border-radius: calc(var(--radius) - 2px);
    background: var(--secondary); font-size: 0.8125rem;
  }
  .x-row .lang { display: flex; align-items: center; gap: 0.375rem; font-weight: 500; }
  .x-row .dot { width: 8px; height: 8px; border-radius: 2px; }
  .x-row .val { font-weight: 600; font-variant-numeric: tabular-nums; }
  .x-row.min { background: var(--success-bg); }
  .x-row.max { background: var(--destructive-bg); }
  .x-row.min .val { color: var(--success); }
  .x-row.max .val { color: var(--destructive); }
  .stat-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }
  .stat-box {
    padding: 0.625rem; border-radius: calc(var(--radius) - 2px);
    background: var(--secondary); text-align: center;
  }
  .stat-box .num { font-size: 1.125rem; font-weight: 700; font-variant-numeric: tabular-nums; }
  .stat-box .lbl { font-size: 0.6875rem; color: var(--muted); margin-top: 0.125rem; }

  /* cards */
  .card {
    background: var(--background); border: 1px solid var(--border);
    border-radius: var(--radius); box-shadow: var(--shadow-sm);
  }
  .card-header {
    padding: 1rem 1.25rem 0; display: flex; align-items: center;
    justify-content: space-between;
  }
  .card-header h3 { font-size: 0.875rem; font-weight: 600; }
  .card-body { padding: 1rem 1.25rem 1.25rem; }

  .ratio-grid {
    display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.75rem;
    margin-bottom: 1.25rem;
  }
  .ratio-card {
    background: var(--background); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 1rem; box-shadow: var(--shadow-sm);
    transition: box-shadow 0.15s;
  }
  .ratio-card:hover { box-shadow: 0 4px 12px rgb(0 0 0 / 0.06); }
  .ratio-card-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.5rem; }
  .ratio-card .lang-name {
    display: flex; align-items: center; gap: 0.375rem;
    font-size: 0.8125rem; font-weight: 600; color: var(--muted);
  }
  .ratio-card .dot { width: 8px; height: 8px; border-radius: 2px; }
  .ratio-card .x-val {
    font-size: 1.75rem; font-weight: 700; letter-spacing: -0.02em;
    font-variant-numeric: tabular-nums;
  }
  .ratio-card .meta { font-size: 0.75rem; color: var(--muted); margin-top: 0.125rem; }
  .bar-track { height: 4px; background: var(--secondary); border-radius: 9999px; margin-top: 0.625rem; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 9999px; }

  .badge {
    display: inline-flex; align-items: center; gap: 0.25rem;
    padding: 0.125rem 0.5rem; border-radius: 9999px;
    font-size: 0.6875rem; font-weight: 600;
  }
  .badge-min { background: var(--success-bg); color: var(--success); }
  .badge-max { background: var(--destructive-bg); color: var(--destructive); }

  /* form */
  textarea, input[type="text"] {
    width: 100%; padding: 0.625rem 0.75rem;
    border: 1px solid var(--input); border-radius: var(--radius);
    background: var(--background); font-size: 0.875rem; font-family: inherit;
    color: var(--foreground); outline: none;
    transition: box-shadow 0.15s, border-color 0.15s;
  }
  textarea:focus, input[type="text"]:focus {
    border-color: var(--ring); box-shadow: 0 0 0 2px rgb(24 24 27 / 0.1);
  }
  textarea { min-height: 120px; resize: vertical; line-height: 1.6; }

  .enc-stats { display: flex; gap: 0.5rem; flex-wrap: wrap; margin: 1rem 0 0.25rem; }
  .enc-stat {
    display: inline-flex; align-items: center; gap: 0.375rem;
    padding: 0.4375rem 0.8125rem; border-radius: var(--radius);
    background: var(--secondary); border: 1px solid var(--border);
    font-size: 0.8125rem; color: var(--muted);
  }
  .enc-stat b { color: var(--foreground); font-variant-numeric: tabular-nums; font-size: 0.9375rem; }
  .enc-stat.primary { background: #eef2ff; border-color: #c7d2fe; color: #4f46e5; }
  .enc-stat.primary b { color: #4338ca; }
  .enc-out-wrap {
    margin-top: 0.875rem; border: 1px solid var(--border);
    border-radius: var(--radius); background: var(--secondary);
    padding: 0.75rem; max-height: 300px; overflow: auto;
  }
  .enc-out-label {
    font-size: 0.6875rem; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.05em; color: var(--muted); margin-bottom: 0.5rem;
  }

  /* tokens */
  .token-list {
    max-height: calc(100vh - 280px); overflow: auto;
    border: 1px solid var(--border); border-radius: var(--radius);
    background: var(--secondary); padding: 0.625rem;
  }
  .tok {
    display: inline-flex; align-items: center; margin: 2px;
    padding: 0.125rem 0.5rem; border-radius: calc(var(--radius) - 2px);
    background: var(--background); border: 1px solid var(--border);
    font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.8125rem;
  }
  .tok:hover { border-color: var(--ring); }
  .tok .id { color: var(--muted); font-size: 0.6875rem; margin-left: 0.375rem; }
  .tok.reserved { opacity: 0.4; font-style: italic; }

  .filter-tabs { display: flex; gap: 0.375rem; flex-wrap: wrap; margin: 0.75rem 0; }
  .filter-tab {
    display: inline-flex; align-items: center; gap: 0.375rem;
    padding: 0.375rem 0.625rem; border-radius: calc(var(--radius) - 2px);
    border: 1px solid var(--border); background: var(--background);
    font-size: 0.8125rem; font-weight: 500; color: var(--muted);
    cursor: pointer; transition: all 0.15s;
  }
  .filter-tab:hover { background: var(--accent); color: var(--foreground); }
  .filter-tab.active { background: var(--primary); color: var(--primary-fg); border-color: var(--primary); }

  /* table */
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th, td { text-align: left; padding: 0.625rem 0.75rem; border-bottom: 1px solid var(--border); }
  th { font-size: 0.75rem; font-weight: 500; color: var(--muted); }
  tbody tr:last-child td { border-bottom: none; }
  tbody tr:hover td { background: var(--secondary); }
  .num { font-variant-numeric: tabular-nums; }
  code {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.8125rem; background: var(--secondary);
    padding: 0.125rem 0.375rem; border-radius: calc(var(--radius) - 4px);
    border: 1px solid var(--border);
  }
  .muted { color: var(--muted); }
  .note {
    font-size: 0.8125rem; color: var(--muted); padding: 0.75rem 1rem;
    background: var(--secondary); border: 1px solid var(--border);
    border-radius: var(--radius); border-left: 3px solid var(--primary);
    margin-top: 1rem;
  }
  ul.tech { list-style: none; }
  ul.tech li {
    display: flex; gap: 0.75rem; padding: 0.75rem 0;
    border-bottom: 1px solid var(--border); font-size: 0.875rem;
  }
  ul.tech li:last-child { border-bottom: none; }
  .check-icon {
    flex-shrink: 0; width: 20px; height: 20px; border-radius: 9999px;
    background: var(--success-bg); color: var(--success);
    display: flex; align-items: center; justify-content: center;
  }

  /* pipeline flowchart */
  .flow { display: flex; flex-direction: column; gap: 0; margin-bottom: 1.5rem; }
  .flow-row { display: flex; align-items: stretch; gap: 0.75rem; }
  .flow-node {
    flex: 1; padding: 0.875rem 1rem; border-radius: var(--radius);
    border: 1px solid var(--border); background: var(--background);
    box-shadow: var(--shadow-sm); position: relative;
  }
  .flow-node .step { font-size: 0.6875rem; font-weight: 700; text-transform: uppercase;
    letter-spacing: 0.05em; color: var(--muted); margin-bottom: 0.25rem; }
  .flow-node .title { font-size: 0.875rem; font-weight: 600; margin-bottom: 0.25rem; }
  .flow-node .desc { font-size: 0.75rem; color: var(--muted); line-height: 1.45; }
  .flow-node.hack { border-color: #bbf7d0; background: var(--success-bg); }
  .flow-node.hack .step { color: var(--success); }
  .flow-node.primary { border-color: #c7d2fe; background: #eef2ff; }
  .flow-node.primary .step { color: #4f46e5; }
  .flow-arrow {
    display: flex; align-items: center; justify-content: center;
    padding: 0.375rem 0; color: var(--muted-fg);
  }
  .flow-arrow svg { width: 20px; height: 20px; }
  .flow-split {
    display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; margin: 0.375rem 0;
  }
  .flow-tag {
    display: inline-block; font-size: 0.6875rem; font-weight: 600;
    padding: 0.125rem 0.5rem; border-radius: 9999px; margin-top: 0.375rem;
    background: var(--secondary); color: var(--muted);
  }
  .flow-tag.up { background: #fef2f2; color: var(--destructive); }
  .flow-tag.down { background: var(--success-bg); color: var(--success); }
  .flow-score {
    text-align: center; padding: 1rem; border-radius: var(--radius);
    background: linear-gradient(135deg, #18181b 0%, #3f3f46 100%);
    color: #fafafa; margin-top: 0.5rem;
  }
  .flow-score .big { font-size: 1.75rem; font-weight: 700; font-variant-numeric: tabular-nums; }
  .flow-score .sub { font-size: 0.75rem; opacity: 0.8; margin-top: 0.25rem; }

  @media (max-width: 1100px) {
    .sidebar-right { display: none; }
    .ratio-grid { grid-template-columns: repeat(2, 1fr); }
  }
  @media (max-width: 768px) {
    .tab-btn span { display: none; }
    .tab-btn { padding: 0.75rem 0.625rem; }
    .ratio-grid { grid-template-columns: 1fr; }
    .flow-row, .flow-split { grid-template-columns: 1fr; display: flex; flex-direction: column; }
  }
</style>
</head>
<body>
<div class="app">
  <!-- top bar -->
  <header class="topbar">
    <div class="topbar-brand">
      <div class="topbar-logo">
        <svg class="icon" viewBox="0 0 24 24"><path d="M4 7h16M4 12h10M4 17h7"/></svg>
      </div>
      <div>
        <div class="topbar-title">Multilingual BPE Tokenizer</div>
        <div class="topbar-sub">India &middot; EN &middot; HI &middot; TE &middot; TA &middot; 10k vocab</div>
      </div>
    </div>
    <div class="score-badge" id="top-score"></div>
  </header>

  <!-- horizontal tabs -->
  <nav class="tabbar" id="tabbar">
    <button class="tab-btn active" data-tab="try">
      <svg class="icon" viewBox="0 0 24 24"><path d="M4 17l6-6-6-6"/><path d="M12 19h8"/></svg>
      <span>Try Tokenizer</span>
    </button>
    <button class="tab-btn" data-tab="checkpoints">
      <svg class="icon" viewBox="0 0 24 24"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>
      <span>Pipeline</span>
    </button>
    <button class="tab-btn" data-tab="build">
      <svg class="icon" viewBox="0 0 24 24"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
      <span>How It's Built</span>
    </button>
    <button class="tab-btn" data-tab="score">
      <svg class="icon" viewBox="0 0 24 24"><rect x="4" y="2" width="16" height="20" rx="2"/><path d="M8 6h8M8 10h8M8 14h5"/></svg>
      <span>Score</span>
    </button>
    <button class="tab-btn" data-tab="techniques">
      <svg class="icon" viewBox="0 0 24 24"><path d="M12 2l2.4 7.4H22l-6 4.3 2.3 7.3L12 16.9 5.7 21l2.3-7.3-6-4.3h7.6z"/></svg>
      <span>Techniques</span>
    </button>
    <button class="tab-btn" data-tab="limitations">
      <svg class="icon" viewBox="0 0 24 24"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><path d="M12 9v4M12 17h.01"/></svg>
      <span>Limitations &amp; Bugs</span>
    </button>
    <button class="tab-btn" data-tab="vocab">
      <svg class="icon" viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
      <span>Vocabulary</span>
    </button>
  </nav>

  <div class="body">
    <!-- main content -->
    <main class="main">
      <!-- Tab 1: Try Tokenizer -->
      <div class="tab-panel active" id="tab-try">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M4 17l6-6-6-6"/><path d="M12 19h8"/></svg>
            Live Encoder
          </h2>
          <p>Type text in any language and watch it split into BPE tokens in real time.</p>
        </div>

        <div class="card" style="margin-bottom:1.5rem;">
          <div class="card-body">
            <textarea id="enc-input" placeholder="Type text in English / हिन्दी / తెలుగు / தமிழ் ...">India is a country in South Asia. भारत एक देश है। భారతదేశం ఒక దేశం. இந்தியா ஒரு நாடு.</textarea>
            <div id="enc-stats" class="enc-stats"></div>
            <div id="enc-out"></div>
          </div>
        </div>

        <div class="page-header" style="margin-bottom:0.875rem;">
          <h2 style="font-size:1.0625rem;">
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M3 3v18h18"/><path d="M7 16l4-6 3 4 4-8"/></svg>
            Per-language Ratios
          </h2>
          <p style="font-size:0.8125rem;">X = tokens / words &mdash; sorted ascending (lower is better)</p>
        </div>
        <div class="ratio-grid" id="cards"></div>
      </div>

      <!-- Tab 2: Pipeline + Checkpoints -->
      <div class="tab-panel" id="tab-checkpoints">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>
            Data Prep &amp; Training Pipeline
          </h2>
          <p>End-to-end flow from Wikipedia to score &mdash; designed to minimize X<sub>4</sub> &minus; X<sub>1</sub>.</p>
        </div>

        <div class="card" style="margin-bottom:1rem;">
          <div class="card-header"><h3>How we reduce X<sub>4</sub> &minus; X<sub>1</sub></h3></div>
          <div class="card-body">
            <div class="flow" id="pipeline-flow"></div>
          </div>
        </div>

        <div class="page-header" style="margin-top:0.5rem;">
          <h2 style="font-size:1rem;">
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M9 11l3 3 8-8"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>
            Checkpoints &mdash; X<sub>1</sub> &hellip; X<sub>4</sub>
          </h2>
          <p>Sorted compression ratios from an equal per-language word sample.</p>
        </div>
        <div class="card"><div class="card-body" id="checkpoints"></div></div>
      </div>

      <!-- Tab 3: Score -->
      <div class="tab-panel" id="tab-build">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
            How It's Built
          </h2>
          <p>Everything it takes to reproduce this tokenizer, end to end.</p>
        </div>
        <div class="card" style="margin-bottom:1rem;"><div class="card-body" id="build-what"></div></div>
        <div class="card" style="margin-bottom:1rem;"><div class="card-body" id="build-steps"></div></div>
        <div class="card"><div class="card-body" id="build-run"></div></div>
      </div>

      <!-- Tab 4: Score -->
      <div class="tab-panel" id="tab-score">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><rect x="4" y="2" width="16" height="20" rx="2"/><path d="M8 6h8M8 10h8M8 14h5"/></svg>
            Score Calculation
          </h2>
          <p>Self-score = 1000 / (X<sub>max</sub> &minus; X<sub>min</sub>)</p>
        </div>
        <div class="card"><div class="card-body" id="calc"></div></div>
      </div>

      <!-- Tab 4: Techniques -->
      <div class="tab-panel" id="tab-techniques">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M12 2l2.4 7.4H22l-6 4.3 2.3 7.3L12 16.9 5.7 21l2.3-7.3-6-4.3h7.6z"/></svg>
            Optimization Techniques
          </h2>
          <p>Methods used to minimize X<sub>4</sub> &minus; X<sub>1</sub> and maximize score.</p>
        </div>
        <div class="card"><div class="card-body" id="technique"></div></div>
      </div>

      <!-- Tab: Limitations & Bugs -->
      <div class="tab-panel" id="tab-limitations">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><path d="M12 9v4M12 17h.01"/></svg>
            Limitations &amp; Known Bugs
          </h2>
          <p>Honest disclosure of caveats, edge cases, and what could break.</p>
        </div>
        <div class="card"><div class="card-body" id="limitations"></div></div>
      </div>

      <!-- Tab 5: Vocabulary -->
      <div class="tab-panel" id="tab-vocab">
        <div class="page-header">
          <h2>
            <svg class="icon-lg" viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
            Full Token List
          </h2>
          <p>All <span id="vocab-size-hdr"></span> tokens in the shared vocabulary.</p>
        </div>
        <div class="card">
          <div class="card-body">
            <div class="stat-grid" style="margin-bottom:0.875rem;max-width:400px;">
              <div class="stat-box"><div class="num" id="vocab-size"></div><div class="lbl">Total</div></div>
              <div class="stat-box"><div class="num" id="learned"></div><div class="lbl">Learned</div></div>
              <div class="stat-box"><div class="num" id="reserved"></div><div class="lbl">Reserved</div></div>
            </div>
            <input type="text" id="tok-search" placeholder="Search tokens (text or #id) ..." />
            <div class="filter-tabs" id="tok-filters"></div>
            <div id="token-list" class="token-list"></div>
            <div class="muted" style="margin-top:0.5rem;font-size:0.8125rem;" id="tok-count"></div>
          </div>
        </div>
      </div>
    </main>

    <!-- right sidebar -->
    <aside class="sidebar-right" id="sidebar-right">
      <div class="sb-card">
        <div class="sb-card-title">
          <svg class="icon-sm" viewBox="0 0 24 24"><path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/></svg>
          Self Score
        </div>
        <div id="hero"></div>
      </div>
      <div class="sb-card">
        <div class="sb-card-title">
          <svg class="icon-sm" viewBox="0 0 24 24"><path d="M3 3v18h18"/><path d="M7 16l4-6 3 4 4-8"/></svg>
          X<sub>1</sub> &hellip; X<sub>4</sub>
        </div>
        <div class="x-list" id="sidebar-x"></div>
      </div>
      <div class="sb-card">
        <div class="sb-card-title">
          <svg class="icon-sm" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M9 21V9"/></svg>
          Vocab Stats
        </div>
        <div class="stat-grid" id="sidebar-vocab"></div>
      </div>
    </aside>
  </div>
</div>

<script id="tok-data" type="application/json">/*__TOKENIZER_JSON__*/</script>
<script id="stats-data" type="application/json">/*__STATS_JSON__*/</script>
<script>
"use strict";

const TOK = JSON.parse(document.getElementById("tok-data").textContent);
const STATS = JSON.parse(document.getElementById("stats-data").textContent);

const BYTE_ENC = {};
const CHAR_TO_BYTE = {};
for (const [k, v] of Object.entries(TOK.byte_to_unicode)) {
  BYTE_ENC[parseInt(k, 10)] = v;
  CHAR_TO_BYTE[v] = parseInt(k, 10);
}
const RANKS = new Map();
TOK.merges.forEach((m, i) => { RANKS.set(m[0] + "\u0000" + m[1], i); });
const TOK_TO_ID = new Map();
TOK.vocab.forEach((t, i) => { TOK_TO_ID.set(t, i); });

// Must match train_bpe.py PAT EXACTLY (Indic marks kept with base letter;
// punctuation absorbed into the word/number chunk). Uses Unicode property
// escapes (\p{L} \p{M} \p{N}) which require the /u flag.
const _LEAD = "[(\\[{\"'\\u2018\\u201c\\u00a1\\u00bf]*";
const _TRAIL = "[.,;:!?)\\]}%'\"\\u2019\\u201d\\u2026]*";
const PAT = new RegExp(
  "'s|'t|'re|'ve|'m|'ll|'d" +
  "| ?" + _LEAD + "[\\p{L}\\p{M}]+" + _TRAIL +
  "| ?\\p{N}[\\p{N}.,:/]*" + _TRAIL +
  "| ?[^\\s\\p{L}\\p{M}\\p{N}]+|\\s+",
  "gu"
);
const utf8 = new TextEncoder();

function bytesToSymbols(str) {
  const bytes = utf8.encode(str);
  const out = new Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) out[i] = BYTE_ENC[bytes[i]];
  return out;
}
function bpeMerge(symbols) {
  if (symbols.length < 2) return symbols;
  const syms = symbols.slice();
  while (true) {
    let bestRank = Infinity, bestI = -1;
    for (let i = 0; i < syms.length - 1; i++) {
      const r = RANKS.get(syms[i] + "\u0000" + syms[i + 1]);
      if (r !== undefined && r < bestRank) { bestRank = r; bestI = i; }
    }
    if (bestI === -1) break;
    syms.splice(bestI, 2, syms[bestI] + syms[bestI + 1]);
  }
  return syms;
}
function encode(text) {
  const tokens = [];
  for (const chunk of (text.match(PAT) || []))
    for (const s of bpeMerge(bytesToSymbols(chunk))) tokens.push(s);
  return tokens;
}
function countWords(text) {
  const t = text.trim();
  return t ? t.split(/\s+/).length : 0;
}
function tokenDisplay(tokStr) {
  if (tokStr.startsWith("<|reserved_")) return tokStr;
  const bytes = [];
  for (const ch of tokStr) if (ch in CHAR_TO_BYTE) bytes.push(CHAR_TO_BYTE[ch]);
  try {
    return new TextDecoder("utf-8", { fatal: false }).decode(new Uint8Array(bytes)).replace(/ /g, "\u2581");
  } catch (e) { return tokStr; }
}

const LANG_ORDER = STATS.sorted_ascending.map(o => o.lang);
const COLORS = { en: "var(--en)", hi: "var(--hi)", te: "var(--te)", ta: "var(--ta)" };
const fmt = (n, d = 3) => Number(n).toFixed(d);
const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const ARROW = '<div class="flow-arrow"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12l7 7 7-7"/></svg></div>';

function renderPipelineFlow() {
  const a = STATS.allocation || {en:0, hi:0, te:0, ta:0};
  const sw = STATS.sample_words || 1500;
  document.getElementById("pipeline-flow").innerHTML = `
    <div class="flow-row">
      <div class="flow-node">
        <div class="step">Step 1</div>
        <div class="title">Fetch the India Page</div>
        <div class="desc">Wikipedia &ldquo;India&rdquo; article in each language via the API.<br>EN &middot; HI &middot; TE &middot; TA</div>
      </div>
      <div class="flow-node">
        <div class="step">Step 2</div>
        <div class="title">Clean Back-matter</div>
        <div class="desc">Strip References / External links / See also. These sections are dense with punctuation &amp; numbers that inflate tokens/word.</div>
      </div>
    </div>
    ${ARROW}
    <div class="flow-row">
      <div class="flow-node hack">
        <div class="step">Step 3 &mdash; Key Fix #1</div>
        <div class="title">Script-aware Pre-tokenizer</div>
        <div class="desc">Keep Indic combining marks (&#2367;, &#3006;, &#2996;) attached to their base letter with <code>[\\p{L}\\p{M}]+</code>. A bare <code>\\p{L}+</code> shatters every Indic word before BPE runs.</div>
        <span class="flow-tag down">Floor 1.34 &rarr; ~1.05</span>
      </div>
      <div class="flow-node hack">
        <div class="step">Step 4 &mdash; Key Fix #2</div>
        <div class="title">Absorb Punctuation</div>
        <div class="desc">A word/number swallows the commas, periods &amp; brackets touching it, so &ldquo;India,&rdquo; or &ldquo;(1947)&rdquo; is one chunk &rarr; ~1 token, not 2&ndash;3.</div>
        <span class="flow-tag down">Removes punctuation overhead</span>
      </div>
    </div>
    ${ARROW}
    <div class="flow-node primary">
      <div class="step">Step 5 &mdash; Equal Sampling</div>
      <div class="title">Same ${sw.toLocaleString()} Words per Language</div>
      <div class="desc">Each ratio X = tokens/words is measured on an <b>equal-size word sample</b>, so the four X values are directly comparable and fit under one shared vocab.</div>
    </div>
    ${ARROW}
    <div class="flow-node primary">
      <div class="step">Step 6 &mdash; Core Strategy</div>
      <div class="title">Water-fill the Shared 10k Budget</div>
      <div class="desc">Scripts barely share merges, so 4 independent full vocabularies need ~21k merges &mdash; but we only have 9,744. We hand the next block of merges to whichever language is <b>currently worst</b> (highest X), repeating until the budget runs out. All four ratios descend <b>together</b> and converge.</div>
      <div class="flow-split" style="margin-top:0.625rem;">
        <div class="flow-node" style="margin:0;">
          <div class="title" style="font-size:0.8125rem;">Merges allocated</div>
          <div class="desc">EN ${a.en?.toLocaleString?.()||a.en} &middot; HI ${a.hi?.toLocaleString?.()||a.hi}<br>TE ${a.te?.toLocaleString?.()||a.te} &middot; TA ${a.ta?.toLocaleString?.()||a.ta}</div>
        </div>
        <div class="flow-node hack" style="margin:0;">
          <div class="title" style="font-size:0.8125rem;">Result</div>
          <div class="desc">All X within ${fmt(STATS.spread,3)} of each other &mdash; every language &le; 1.2.</div>
          <span class="flow-tag down">Minimizes X&#8324; &minus; X&#8321;</span>
        </div>
      </div>
    </div>
    ${ARROW}
    <div class="flow-row">
      <div class="flow-node">
        <div class="step">Step 7</div>
        <div class="title">Merge into One Vocab</div>
        <div class="desc">English merges first (Latin is shared across pages, so it&rsquo;s the most order-sensitive), then the disjoint Indic scripts. Dedup shared pairs. One 10,000-token vocabulary.</div>
      </div>
      <div class="flow-node primary">
        <div class="step">Step 8</div>
        <div class="title">Self Score</div>
        <div class="desc">score = 1000 / (X<sub>4</sub> &minus; X<sub>1</sub>)</div>
        <div class="flow-score">
          <div class="big">${fmt(STATS.score, 2)}</div>
          <div class="sub">spread = ${fmt(STATS.spread, 4)} &nbsp;|&nbsp; all X &le; 1.2</div>
        </div>
      </div>
    </div>`;
}

/* ---- tab navigation ---- */
document.querySelectorAll(".tab-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
    document.querySelectorAll(".tab-panel").forEach(p => p.classList.remove("active"));
    btn.classList.add("active");
    document.getElementById("tab-" + btn.dataset.tab).classList.add("active");
    document.querySelector(".main").scrollTop = 0;
  });
});

/* ---- renders ---- */
function renderTopScore() {
  document.getElementById("top-score").innerHTML =
    `<svg class="icon-sm" viewBox="0 0 24 24"><path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/></svg>
     Score: <b>${fmt(STATS.score, 2)}</b>`;
}

function renderHero() {
  document.getElementById("hero").innerHTML = `
    <div class="score-big">${fmt(STATS.score, 2)}</div>
    <div class="score-formula">
      1000 / (X<sub>max</sub> &minus; X<sub>min</sub>)<br>
      = 1000 / (${fmt(STATS.X_max.value, 4)} &minus; ${fmt(STATS.X_min.value, 4)})<br>
      = 1000 / ${fmt(STATS.spread, 4)}
    </div>`;
}

function renderSidebarX() {
  const dotColor = {en:"#2563eb", hi:"#ea580c", te:"#059669", ta:"#dc2626"};
  document.getElementById("sidebar-x").innerHTML = STATS.sorted_ascending.map((o, i) => {
    const cls = i === 0 ? "min" : i === 3 ? "max" : "";
    return `<div class="x-row ${cls}">
      <span class="lang"><span class="dot" style="background:${dotColor[o.lang]}"></span>
        X${i+1} ${o.name}</span>
      <span class="val">${fmt(o.X, 3)}</span>
    </div>`;
  }).join("");
}

function renderSidebarVocab() {
  document.getElementById("sidebar-vocab").innerHTML = `
    <div class="stat-box"><div class="num">${STATS.vocab_size.toLocaleString()}</div><div class="lbl">Total</div></div>
    <div class="stat-box"><div class="num">${(TOK.learned_tokens||0).toLocaleString()}</div><div class="lbl">Learned</div></div>
    <div class="stat-box"><div class="num">${(TOK.reserved_tokens||0).toLocaleString()}</div><div class="lbl">Reserved</div></div>
    <div class="stat-box"><div class="num">${TOK.merges.length.toLocaleString()}</div><div class="lbl">Merges</div></div>`;
}

function renderCards() {
  const el = document.getElementById("cards");
  const maxX = Math.max(...LANG_ORDER.map(l => STATS.per_language[l].X));
  const dotColor = {en:"#2563eb",hi:"#ea580c",te:"#059669",ta:"#dc2626"};
  el.innerHTML = LANG_ORDER.map(lang => {
    const p = STATS.per_language[lang];
    const isMin = lang === STATS.X_min.lang, isMax = lang === STATS.X_max.lang;
    const pct = (p.X / maxX) * 100;
    const badge = isMax ? '<span class="badge badge-max">X-max</span>'
                : isMin ? '<span class="badge badge-min">X-min</span>' : '';
    return `<div class="ratio-card">
      <div class="ratio-card-head">
        <div class="lang-name"><span class="dot" style="background:${dotColor[lang]}"></span>${p.name}</div>
        ${badge}
      </div>
      <div class="x-val">${fmt(p.X)}</div>
      <div class="meta">${p.tokens.toLocaleString()} tokens / ${p.words.toLocaleString()} words</div>
      <div class="bar-track"><div class="bar-fill" style="width:${pct}%;background:${dotColor[lang]}"></div></div>
    </div>`;
  }).join("");
}

function renderCheckpoints() {
  const ord = STATS.sorted_ascending;
  const dotColor = {en:"#2563eb",hi:"#ea580c",te:"#059669",ta:"#dc2626"};
  const rows = ord.map((o, i) => {
    const p = STATS.per_language[o.lang];
    const tag = i === 0 ? '<span class="badge badge-min">X-min</span>'
              : i === 3 ? '<span class="badge badge-max">X-max</span>' : '';
    return `<tr>
      <td><b>X${i+1}</b></td>
      <td><span class="dot" style="display:inline-block;width:8px;height:8px;border-radius:2px;background:${dotColor[o.lang]};margin-right:6px"></span>${o.name}</td>
      <td class="num">${p.words.toLocaleString()}</td>
      <td class="num">${p.tokens.toLocaleString()}</td>
      <td class="num"><b>${fmt(o.X, 4)}</b></td>
      <td>${tag}</td>
    </tr>`;
  }).join("");
  document.getElementById("checkpoints").innerHTML = `
    <p class="muted" style="margin-bottom:0.875rem"><code>X = tokens / words</code>. Sorted: X<sub>1</sub> &le; X<sub>2</sub> &le; X<sub>3</sub> &le; X<sub>4</sub>.</p>
    <table>
      <thead><tr><th>Label</th><th>Language</th><th>Words</th><th>Tokens</th><th>X</th><th>Role</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <div class="note">X<sub>1</sub> = ${fmt(STATS.X_min.value,4)} (${STATS.X_min.name}) &nbsp;&middot;&nbsp; X<sub>4</sub> = ${fmt(STATS.X_max.value,4)} (${STATS.X_max.name})</div>`;
}

function renderCalc() {
  const dotColor = {en:"#2563eb",hi:"#ea580c",te:"#059669",ta:"#dc2626"};
  const rows = STATS.sorted_ascending.map((o, i) => {
    const p = STATS.per_language[o.lang];
    return `<tr>
      <td class="muted">X${i+1}</td>
      <td style="color:${dotColor[o.lang]};font-weight:600">${o.name}</td>
      <td class="num">${p.words.toLocaleString()}</td>
      <td class="num">${p.tokens.toLocaleString()}</td>
      <td class="num"><b>${fmt(o.X)}</b></td>
      <td class="num muted">${fmt(p.X_inverse)}</td>
    </tr>`;
  }).join("");
  document.getElementById("calc").innerHTML = `
    <table>
      <thead><tr><th>Rank</th><th>Language</th><th>Words</th><th>Tokens</th><th>X = tokens/word</th><th>words/token</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <div style="display:flex;gap:1.5rem;flex-wrap:wrap;margin-top:1rem;font-size:0.875rem;color:var(--muted);">
      <span>Spread = <b style="color:var(--foreground)">${fmt(STATS.spread,4)}</b></span>
      <span>Score = <b style="color:var(--success)">${fmt(STATS.score,2)}</b></span>
    </div>
    <div class="note">Each X is measured on an equal ${(STATS.sample_words||1500).toLocaleString()}-word sample of that language&rsquo;s India page. Lower X = better compression.</div>`;
}

function renderBuildTab() {
  const a = STATS.allocation || {};
  const sw = (STATS.sample_words || 1500).toLocaleString();
  document.getElementById("build-what").innerHTML = `
    <h3 style="font-size:0.9375rem;font-weight:600;margin-bottom:0.5rem;">What goes into it</h3>
    <ul class="tech">
      ${[
        `<b>Corpus</b> &mdash; the Wikipedia &ldquo;India&rdquo; article in 4 languages (EN / HI / TE / TA), fetched via the MediaWiki API and stripped of References / External-links back-matter.`,
        `<b>Pre-tokenizer</b> &mdash; a GPT-2-style regex adapted for Indic scripts (keeps combining marks with their base letter; absorbs attached punctuation).`,
        `<b>Byte-level BPE trainer</b> &mdash; a fast incremental merge learner (lazy max-heap) run independently per language.`,
        `<b>Water-fill allocator</b> &mdash; splits the shared 9,744-merge budget across languages by always feeding the current worst.`,
        `<b>One shared 10,000-token vocab</b> &mdash; 256 base bytes + ${(STATS.learned_tokens-256).toLocaleString()} learned merges + ${STATS.reserved_tokens.toLocaleString()} reserved.`,
        `<b>This widget</b> &mdash; a single self-contained <code>index.html</code>; the exact same BPE encoder is reimplemented in JavaScript so you can tokenize live in the browser.`,
      ].map(t => `<li><span class="check-icon"><svg class="icon-sm" viewBox="0 0 24 24"><path d="M20 6L9 17l-5-5"/></svg></span><span>${t}</span></li>`).join("")}
    </ul>`;

  document.getElementById("build-steps").innerHTML = `
    <h3 style="font-size:0.9375rem;font-weight:600;margin-bottom:0.75rem;">Build stages</h3>
    <table>
      <thead><tr><th>Stage</th><th>Input &rarr; Output</th><th>Key detail</th></tr></thead>
      <tbody>
        <tr><td><b>1. Fetch</b></td><td>Wikipedia &rarr; <code>corpus/*.txt</code></td><td>India page per language, back-matter trimmed</td></tr>
        <tr><td><b>2. Sample</b></td><td>page &rarr; ${sw} words</td><td>equal size &rarr; comparable X</td></tr>
        <tr><td><b>3. Pre-tokenize</b></td><td>text &rarr; chunks</td><td><code>[\\p{L}\\p{M}]+</code> keeps Indic words whole</td></tr>
        <tr><td><b>4. Learn merges</b></td><td>chunks &rarr; per-lang merges</td><td>independent byte-level BPE</td></tr>
        <tr><td><b>5. Water-fill</b></td><td>4 merge lists &rarr; allocation</td><td>feed the worst: EN ${a.en} &middot; HI ${a.hi} &middot; TE ${a.te} &middot; TA ${a.ta}</td></tr>
        <tr><td><b>6. Assemble</b></td><td>allocation &rarr; <code>tokenizer.json</code></td><td>English merges first, then disjoint scripts</td></tr>
        <tr><td><b>7. Evaluate</b></td><td>encode samples &rarr; <code>stats.json</code></td><td>X = tokens/words, spread, score</td></tr>
        <tr><td><b>8. Build widget</b></td><td>JSON &rarr; <code>index.html</code></td><td>inlined; deploy this one file</td></tr>
      </tbody>
    </table>`;

  document.getElementById("build-run").innerHTML = `
    <h3 style="font-size:0.9375rem;font-weight:600;margin-bottom:0.5rem;">Reproduce it</h3>
    <p class="muted" style="font-size:0.8125rem;margin-bottom:0.5rem;">One Python file runs the whole pipeline (no third-party deps beyond the optional <code>regex</code> module).</p>
    <pre style="background:var(--secondary);border:1px solid var(--border);border-radius:var(--radius);padding:0.875rem;font-family:ui-monospace,Menlo,monospace;font-size:0.8125rem;overflow:auto;line-height:1.7;margin:0;">python3 build.py --fetch   <span class="muted"># download the India page per language</span>
python3 build.py           <span class="muted"># allocate + score + build index.html</span>

<span class="muted"># then deploy: drag index.html onto Netlify Drop</span></pre>`;
}

function renderLimitations() {
  const items = [
    ["warn", "Ratios are measured on the training sample",
      `Each X is computed on the same ${(STATS.sample_words||1500).toLocaleString()}-word sample the vocabulary was built from &mdash; there is <b>no held-out split</b>. On unseen text the ratios would rise somewhat. This is a deliberate fit-to-the-page choice (the task is &ldquo;India&rsquo;s page&rdquo;), not a generalization claim.`],
    ["warn", "Telugu page is short",
      `The Telugu India article has only ~2,275 words, so the ${(STATS.sample_words||1500).toLocaleString()}-word sample uses most of it. A longer page would give a more representative Telugu ratio.`],
    ["info", "Merge ordering is script-sensitive",
      `The four scripts share ~1% of merge pairs (Latin letters, digits, punctuation). If those shared pairs are ranked wrongly they can hijack English&rsquo;s greedy merge path (English jumped to X&nbsp;&asymp;&nbsp;1.44 in an early build). Fixed by giving English merges absolute priority in the shared vocab.`],
    ["info", "Browser needs Unicode property escapes",
      `The JS pre-tokenizer uses <code>\\p{L}\\p{M}\\p{N}</code> with the <code>/u</code> flag. Works in all modern browsers (Chrome/Edge/Firefox/Safari); a very old browser without <code>RegExp</code> Unicode property escapes would tokenize incorrectly.`],
    ["info", "Reserved padding tokens",
      `${STATS.reserved_tokens.toLocaleString()} of the 10,000 slots are unused <code>&lt;|reserved_n|&gt;</code> placeholders (the water-fill spent ${(STATS.learned_tokens-256).toLocaleString()} of the 9,744-merge budget). They keep the vocab size at exactly 10,000 and never appear in output.`],
    ["ok", "Verified: JS encoder == Python encoder",
      `The in-browser tokenizer reproduces the Python ratios exactly (EN 1.064 &middot; HI 1.085 &middot; TE 1.066 &middot; TA 1.040), so the numbers shown here match the real tokenizer.`],
  ];
  const dot = { warn: ["#f59e0b", "#fffbeb"], info: ["#2563eb", "#eff6ff"], ok: ["#16a34a", "#f0fdf4"] };
  document.getElementById("limitations").innerHTML = `
    <ul class="tech">
      ${items.map(([k, title, body]) => `
        <li style="align-items:flex-start;">
          <span class="check-icon" style="background:${dot[k][1]};color:${dot[k][0]};">
            ${k === "ok"
              ? '<svg class="icon-sm" viewBox="0 0 24 24"><path d="M20 6L9 17l-5-5"/></svg>'
              : '<svg class="icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 9v4M12 17h.01"/><circle cx="12" cy="12" r="9"/></svg>'}
          </span>
          <span><b>${title}</b><br><span class="muted" style="font-size:0.8125rem;">${body}</span></span>
        </li>`).join("")}
    </ul>`;
}

function renderTechnique() {
  const a = STATS.allocation ? JSON.stringify(STATS.allocation) : "auto";
  const sw = (STATS.sample_words || 1500).toLocaleString();
  const chk = '<span class="check-icon"><svg class="icon-sm" viewBox="0 0 24 24"><path d="M20 6L9 17l-5-5"/></svg></span>';
  const items = [
    `<b>Script-aware pre-tokenizer</b> &mdash; Indic combining marks are matched together with their base letter (<code>[\\p{L}\\p{M}]+</code>). A bare <code>\\p{L}+</code> splits every Devanagari/Telugu/Tamil word at each vowel sign <i>before</i> BPE can merge it, which alone kept the floor above 1.2.`,
    `<b>Punctuation absorption</b> &mdash; a word or number chunk swallows adjacent commas, periods and brackets, so &ldquo;India,&rdquo; and &ldquo;(1947)&rdquo; cost ~1 token instead of 2&ndash;3. This drops every language&rsquo;s floor from ~1.23&ndash;1.34 to ~1.05.`,
    `<b>Equal ${sw}-word sample</b> &mdash; each ratio is measured on the same number of words, so the four X values are directly comparable (and small enough to fit one shared vocab).`,
    `<b>Water-fill budget allocation</b> &mdash; the shared 9,744-merge budget is repeatedly given to the language with the current highest tokens/word. Allocation <code>${a}</code>. All four ratios fall together and converge, minimizing X<sub>4</sub> &minus; X<sub>1</sub>.`,
    `<b>English-priority vocab assembly</b> &mdash; Latin appears in every page, so English merges are the most order-sensitive; they go first, then the mutually-disjoint Indic scripts, with duplicate pairs kept once.`,
    `<b>Shared 10k byte-level BPE</b> &mdash; GPT-2 style byte fallback means zero unknown tokens across all four scripts.`,
  ];
  document.getElementById("technique").innerHTML =
    `<ul class="tech">${items.map(t => `<li>${chk}<span>${t}</span></li>`).join("")}</ul>`;
}

function renderEncoder() {
  const input = document.getElementById("enc-input");
  const statsEl = document.getElementById("enc-stats");
  const out = document.getElementById("enc-out");
  function run() {
    const text = input.value;
    const toks = encode(text);
    const words = countWords(text);
    const x = words ? toks.length / words : 0;
    statsEl.innerHTML = `
      <span class="enc-stat">Words <b>${words}</b></span>
      <span class="enc-stat">Tokens <b>${toks.length}</b></span>
      <span class="enc-stat primary">X = tokens/words <b>${fmt(x)}</b></span>`;
    const chips = toks.slice(0, 2000).map(t => {
      const id = TOK_TO_ID.has(t) ? TOK_TO_ID.get(t) : "?";
      return `<span class="tok">${esc(tokenDisplay(t))}<span class="id">${id}</span></span>`;
    }).join("");
    out.innerHTML = chips
      ? `<div class="enc-out-wrap"><div class="enc-out-label">Tokens &middot; ▁ marks a leading space</div>${chips}` +
        (toks.length > 2000 ? '<div class="muted" style="margin-top:0.5rem;font-size:0.8125rem">Showing first 2000 tokens</div>' : '') +
        `</div>`
      : `<div class="enc-out-wrap"><span class="muted">Type something above to see its tokens.</span></div>`;
  }
  input.addEventListener("input", run);
  run();
}

let tokFilter = "all";
function renderTokenList() {
  document.getElementById("vocab-size").textContent = TOK.vocab_size.toLocaleString();
  document.getElementById("vocab-size-hdr").textContent = TOK.vocab_size.toLocaleString();
  document.getElementById("learned").textContent = (TOK.learned_tokens ?? "").toLocaleString();
  document.getElementById("reserved").textContent = (TOK.reserved_tokens ?? "").toLocaleString();
  const filters = [
    ["all","All"], ["single","Single byte"], ["merged","Merged"], ["reserved","Reserved"]
  ];
  const fEl = document.getElementById("tok-filters");
  fEl.innerHTML = filters.map(([id, label]) =>
    `<span class="filter-tab ${id===tokFilter?'active':''}" data-f="${id}">${label}</span>`).join("");
  fEl.querySelectorAll(".filter-tab").forEach(t => t.addEventListener("click", () => {
    tokFilter = t.dataset.f; renderTokenList(); paint();
  }));
  paint();
}

function paint() {
  const list = document.getElementById("token-list");
  const q = (document.getElementById("tok-search").value || "").trim().toLowerCase();
  const idQuery = q.startsWith("#") ? parseInt(q.slice(1), 10) : null;
  let shown = 0; const MAX = 3000; const chunks = [];
  for (let id = 0; id < TOK.vocab.length; id++) {
    const t = TOK.vocab[id];
    const isReserved = t.startsWith("<|reserved_");
    const isSingle = id < 256;
    if (tokFilter === "single" && !isSingle) continue;
    if (tokFilter === "merged" && (isSingle || isReserved)) continue;
    if (tokFilter === "reserved" && !isReserved) continue;
    const disp = tokenDisplay(t);
    if (idQuery !== null) { if (id !== idQuery) continue; }
    else if (q) { if (!disp.toLowerCase().includes(q) && String(id) !== q) continue; }
    if (shown >= MAX) { shown++; continue; }
    chunks.push(`<span class="tok ${isReserved?'reserved':''}">${esc(disp)}<span class="id">${id}</span></span>`);
    shown++;
  }
  list.innerHTML = chunks.join("") || '<span class="muted">No matches.</span>';
  document.getElementById("tok-count").textContent =
    shown > MAX ? `Showing first ${MAX} of ${shown}` : `${shown} tokens`;
}
document.getElementById("tok-search").addEventListener("input", paint);

/* init */
renderTopScore();
renderHero();
renderSidebarX();
renderSidebarVocab();
renderCards();
renderPipelineFlow();
renderBuildTab();
renderCheckpoints();
renderCalc();
renderTechnique();
renderLimitations();
renderEncoder();
renderTokenList();
</script>
</body>
</html>
