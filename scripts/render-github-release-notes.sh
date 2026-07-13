#!/usr/bin/env bash
set -euo pipefail

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

require_value RELEASE_TAG
require_value VERSION
require_value RELEASE_NOTES_MARKDOWN
require_value RELEASE_NOTES_HTML

if [[ -n "${RELEASE_NOTES_SOURCE:-}" ]]; then
  test -f "$RELEASE_NOTES_SOURCE"
  cp "$RELEASE_NOTES_SOURCE" "$RELEASE_NOTES_MARKDOWN"
else
  gh release view "$RELEASE_TAG" --json body --jq .body > "$RELEASE_NOTES_MARKDOWN"
fi

ruby -r cgi - "$VERSION" "$RELEASE_NOTES_MARKDOWN" "$RELEASE_NOTES_HTML" <<'RUBY'
version, markdown_path, html_path = ARGV
lines = File.readlines(markdown_path, chomp: true)
lines.shift while lines.first&.strip&.empty?
lines.pop while lines.last&.strip&.empty?

abort "The published GitHub Release description must not be empty." if lines.empty?

File.write(markdown_path, "#{lines.join("\n")}\n")

escape = ->(text) { CGI.escapeHTML(text) }
content = []
in_list = false

lines.each do |line|
  if (match = line.match(/^\s*[-*]\s+(.+)$/))
    unless in_list
      content << "<ul>"
      in_list = true
    end
    content << "  <li>#{escape.call(match[1].strip)}</li>"
  else
    if in_list
      content << "</ul>"
      in_list = false
    end
    content << "<p>#{escape.call(line.strip)}</p>" unless line.strip.empty?
  end
end
content << "</ul>" if in_list

File.write(html_path, <<~HTML)
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PlayStatus #{escape.call(version)}</title>
    <style>
      :root { color-scheme: light dark; }
      body { font: -apple-system-body; line-height: 1.45; margin: 0; padding: 20px; }
      main { max-width: 680px; margin: 0 auto; }
      h1 { font: -apple-system-title1; margin: 0 0 14px; }
      p, ul { margin: 0 0 12px; }
      ul { padding-left: 22px; }
    </style>
  </head>
  <body>
    <main>
      <h1>PlayStatus #{escape.call(version)}</h1>
      #{content.join("\n      ")}
    </main>
  </body>
  </html>
HTML
RUBY

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "markdown_path=$RELEASE_NOTES_MARKDOWN"
    echo "html_path=$RELEASE_NOTES_HTML"
  } >> "$GITHUB_OUTPUT"
fi
