#!/usr/bin/env bash
# Copy of the web build with relative paths, for previews hosted at any path (e.g. an Artifact).
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf demo && mkdir -p demo/js
JS=$(ls dist/_expo/static/js/web/)
sed 's#"/app/assets/#"./assets/#g' "dist/_expo/static/js/web/$JS" > "demo/js/$JS"
cp -r dist/assets demo/assets
cat > demo/index.html <<HTML
<title>NussNuss App</title>
<meta name="description" content="NussNuss web build: split bills with no limits.">
<style>
  :root { --bg: #F7F6FB; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0F0D1A; color-scheme: dark; } }
  :root[data-theme="dark"] { --bg: #0F0D1A; color-scheme: dark; }
  html, body { height: 100%; }
  body { overflow: hidden; background: var(--bg); }
  #root { display: flex; height: 100%; flex: 1; }
</style>
<noscript>NussNuss needs JavaScript.</noscript>
<div id="root"></div>
<script src="./js/$JS" defer></script>
HTML
echo "demo/ built ($JS)"
