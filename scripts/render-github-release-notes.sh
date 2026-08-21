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

ruby -r cgi - "$RELEASE_NOTES_MARKDOWN" "$RELEASE_NOTES_HTML" <<'RUBY'
markdown_path, html_path = ARGV
lines = File.readlines(markdown_path, chomp: true)
lines.shift while lines.first&.strip&.empty?
lines.pop while lines.last&.strip&.empty?

abort "The published GitHub Release description must not be empty." if lines.empty?

File.write(markdown_path, "#{lines.join("\n")}\n")

escape = ->(text) { CGI.escapeHTML(text) }

format_inline = nil
format_inline = lambda do |text|
  result = +""
  remaining = text
  pattern = /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)|(\*\*|__)(.+?)\4|~~(.+?)~~|(?<!\w)([_*])(.+?)\7(?!\w)/

  until remaining.empty?
    match = remaining.match(pattern)
    unless match
      result << escape.call(remaining)
      break
    end

    result << escape.call(remaining[0...match.begin(0)])
    if match[1]
      result << "<code>#{escape.call(match[1])}</code>"
    elsif match[2]
      label = format_inline.call(match[2])
      href = match[3]
      if href.match?(%r{\A(?:https?://|mailto:)})
        result << %(<a href="#{escape.call(href)}">#{label}</a>)
      else
        result << label
      end
    elsif match[4]
      result << "<strong>#{format_inline.call(match[5])}</strong>"
    elsif match[6]
      result << "<del>#{format_inline.call(match[6])}</del>"
    else
      result << "<em>#{format_inline.call(match[8])}</em>"
    end
    remaining = remaining[match.end(0)..].to_s
  end

  result
end

heading = ->(line) { line.match(/^(\#{1,6})\s+(.+?)\s*#*\s*$/) }
unordered_item = ->(line) { line.match(/^\s*[-*+]\s+(.+)$/) }
ordered_item = ->(line) { line.match(/^\s*\d+[.)]\s+(.+)$/) }

# GitHub-flavored tables. Split on unescaped pipes, tolerating the optional
# leading and trailing pipe that most authors write.
split_row = lambda do |line|
  cells = line.strip
  cells = cells[1..].to_s if cells.start_with?("|")
  cells = cells[0..-2].to_s if cells.end_with?("|") && !cells.end_with?("\\|")
  cells.split(/(?<!\\)\|/).map { |cell| cell.strip.gsub("\\|", "|") }
end

# The `| --- | :---: |` row directly under the header. Its cell count is what
# makes a line of prose containing a pipe not a table.
delimiter_row = lambda do |line|
  return false unless line.include?("-")
  cells = split_row.call(line)
  !cells.empty? && cells.all? { |cell| cell.match?(/\A:?-+:?\z/) }
end

alignment_of = lambda do |cell|
  left = cell.start_with?(":")
  right = cell.end_with?(":")
  if left && right then "center"
  elsif right then "right"
  elsif left then "left"
  end
end

table_start = lambda do |idx|
  header = lines[idx]
  divider = lines[idx + 1]
  return false if header.nil? || divider.nil?
  return false unless header.include?("|")
  return false unless delimiter_row.call(divider)
  split_row.call(header).length == split_row.call(divider).length
end

block_start = lambda do |line|
  line.strip.empty? || line.start_with?("```") || heading.call(line) ||
    unordered_item.call(line) || ordered_item.call(line) ||
    line.match?(/^\s*>\s?/) || line.match?(/^\s{0,3}(?:---+|\*\*\*+|___+)\s*$/)
end

content = []
index = 0
while index < lines.length
  line = lines[index]
  if line.strip.empty?
    index += 1
    next
  end

  if line.start_with?("```")
    code = []
    index += 1
    while index < lines.length && !lines[index].start_with?("```")
      code << lines[index]
      index += 1
    end
    abort "Unterminated fenced code block in GitHub Release description." if index == lines.length
    content << "<pre><code>#{escape.call(code.join("\n"))}</code></pre>"
    index += 1
  elsif (match = heading.call(line))
    level = [match[1].length, 3].min
    content << "<h#{level}>#{format_inline.call(match[2].strip)}</h#{level}>"
    index += 1
  elsif line.match?(/^\s{0,3}(?:---+|\*\*\*+|___+)\s*$/)
    content << "<hr>"
    index += 1
  elsif line.match?(/^\s*>\s?/)
    quote = []
    while index < lines.length && lines[index].match?(/^\s*>\s?/)
      quote << lines[index].sub(/^\s*>\s?/, "").strip
      index += 1
    end
    content << "<blockquote><p>#{format_inline.call(quote.join(" "))}</p></blockquote>"
  elsif (item = unordered_item.call(line)) || (item = ordered_item.call(line))
    tag = unordered_item.call(line) ? "ul" : "ol"
    items = []
    matcher = tag == "ul" ? unordered_item : ordered_item
    while index < lines.length && (match = matcher.call(lines[index]))
      items << "  <li>#{format_inline.call(match[1].strip)}</li>"
      index += 1
    end
    content << "<#{tag}>\n#{items.join("\n")}\n</#{tag}>"
  elsif table_start.call(index)
    headers = split_row.call(lines[index])
    aligns = split_row.call(lines[index + 1]).map { |cell| alignment_of.call(cell) }
    index += 2

    cell_tag = lambda do |tag, text, align|
      style = align ? %( style="text-align: #{align}") : ""
      "<#{tag}#{style}>#{format_inline.call(text)}</#{tag}>"
    end

    head = headers.each_with_index.map { |text, i| cell_tag.call("th", text, aligns[i]) }
    body = []
    while index < lines.length && lines[index].include?("|") && !lines[index].strip.empty?
      row = split_row.call(lines[index])
      # Pad or trim to the header width so a ragged row cannot shift the columns.
      row = row[0, headers.length] + [""] * [headers.length - row.length, 0].max
      body << "    <tr>#{row.each_with_index.map { |text, i| cell_tag.call('td', text, aligns[i]) }.join}</tr>"
      index += 1
    end

    table = +"<div class=\"table-wrap\">\n  <table>\n"
    table << "    <thead><tr>#{head.join}</tr></thead>\n"
    table << "    <tbody>\n#{body.join("\n")}\n    </tbody>\n" unless body.empty?
    table << "  </table>\n</div>"
    content << table
  else
    paragraph = []
    while index < lines.length && !block_start.call(lines[index]) && !table_start.call(index)
      paragraph << lines[index].strip
      index += 1
    end
    content << "<p>#{format_inline.call(paragraph.join(" "))}</p>" unless paragraph.empty?
  end
end

File.write(html_path, <<~HTML)
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      body {
        margin: 0;
        color: -apple-system-label;
        font: 16px/1.48 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        text-rendering: optimizeLegibility;
      }
      main { padding: 20px 24px 28px; }
      h1, h2, h3 { color: inherit; letter-spacing: -0.01em; }
      h1 { font-size: 22px; line-height: 1.2; margin: 0 0 14px; }
      h2 { border-top: 1px solid color-mix(in srgb, currentColor 16%, transparent); font-size: 17px; line-height: 1.3; margin: 25px 0 10px; padding-top: 18px; }
      h2:first-child { border-top: 0; margin-top: 0; padding-top: 0; }
      h3 { font-size: 15px; line-height: 1.35; margin: 20px 0 7px; }
      p { margin: 0 0 14px; }
      ul, ol { margin: 0 0 16px; padding-left: 22px; }
      li { margin: 7px 0; padding-left: 2px; }
      li::marker { color: #0A84FF; }
      strong { font-weight: 650; }
      em { color: color-mix(in srgb, currentColor 76%, transparent); }
      code { background: color-mix(in srgb, currentColor 12%, transparent); border-radius: 5px; font: 0.88em ui-monospace, SFMono-Regular, Menlo, monospace; padding: 2px 5px; overflow-wrap: anywhere; }
      pre { background: color-mix(in srgb, currentColor 9%, transparent); border-radius: 8px; margin: 0 0 16px; overflow-x: auto; padding: 12px; }
      pre code { background: transparent; padding: 0; }
      .table-wrap { margin: 0 0 16px; overflow-x: auto; }
      table { border-collapse: collapse; font-size: 0.94em; width: 100%; }
      th, td { border-bottom: 1px solid color-mix(in srgb, currentColor 14%, transparent); padding: 7px 14px 7px 0; text-align: left; vertical-align: top; }
      th { font-weight: 650; }
      tbody tr:last-child td { border-bottom: 0; }
      blockquote { border-left: 3px solid #0A84FF; margin: 0 0 16px; padding-left: 13px; }
      blockquote p { margin: 0; }
      a { color: #0A84FF; text-decoration: none; }
      a:hover { text-decoration: underline; }
      hr { border: 0; border-top: 1px solid color-mix(in srgb, currentColor 16%, transparent); margin: 22px 0; }
    </style>
  </head>
  <body>
    <main>
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
