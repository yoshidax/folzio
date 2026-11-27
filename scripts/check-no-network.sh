#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Fails when Sources refers to a network API or a URL, except on the lines listed below.
#
# The app communicates only for the update check (TAK-95): one GitHub API request, started from the menu or by the
# automatic check the user agreed to. Every allowed line is tied to one file, and a line is allowed only when it
# contains nothing else that the check looks for.
# - Sources/FolzioCore/About/AboutInfo.swift: the public repository link shown by the About dialog (TAK-45).
#   The app never requests it; it only hands the URL to the OS, which opens it in the default web browser.
#   The update check builds the release page URL from it.
# - Sources/FolzioCore/Operations/ImportedFileName.swift: the scheme comparison used to name imported files.
# - Sources/FolzioCore/Update/UpdateSource.swift: the API URL of the latest release, and no other URL.
# - Sources/FolzioApp/Update/URLSessionUpdateTransport.swift: URLSession, the only place that sends a request.
# NWConnection and the Network framework are never allowed.

pattern='URLSession|NWConnection|import[[:space:]]+Network|\bhttp\b|https?://'

matches=$(
    grep -rnE "$pattern" Sources --include='*.swift' |
        awk '
            function rest_is_clean(text) {
                return text !~ /URLSession|NWConnection|import[[:space:]]+Network|(^|[^[:alnum:]_])http([^[:alnum:]_]|$)|https?:\/\//
            }
            function without(text, literal,    position) {
                position = index(text, literal)
                if (position == 0) return ""
                return substr(text, 1, position - 1) substr(text, position + length(literal))
            }
            {
                file = $0
                sub(/:[0-9]+:.*$/, "", file)
                line = $0
                sub(/^[^:]+:[0-9]+:/, "", line)
            }
            file == "Sources/FolzioCore/About/AboutInfo.swift" {
                literal = "\"https://github.com/yoshidax/folzio\""
                if (index(line, literal) && rest_is_clean(without(line, literal))) next
            }
            file == "Sources/FolzioCore/Operations/ImportedFileName.swift" {
                if (line ~ /^[[:space:]]*\["http", "https"\]\.contains\(scheme\),[[:space:]]*$/) next
            }
            file == "Sources/FolzioCore/Update/UpdateSource.swift" {
                literal = "\"https://api.github.com/repos/yoshidax/folzio/releases/latest\""
                if (index(line, literal) && rest_is_clean(without(line, literal))) next
            }
            file == "Sources/FolzioApp/Update/URLSessionUpdateTransport.swift" {
                stripped = line
                gsub(/URLSession/, "", stripped)
                if (index(line, "URLSession") && rest_is_clean(stripped)) next
            }
            { print }
        ' || true
)

if [[ -n "$matches" ]]; then
    echo "$matches"
    echo "network API reference found in Sources" >&2
    exit 1
fi

echo "no network API references in Sources"
