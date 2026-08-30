#!/usr/bin/env bash
# Builds the site and asserts on rendered output.
set -uo pipefail

HUGO="${HUGO_BIN:-hugo}"
if ! command -v "$HUGO" >/dev/null 2>&1; then
  HUGO="/c/Users/angus/AppData/Local/Microsoft/WinGet/Packages/Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe/hugo.exe"
fi

OUT="$(pwd)/.verify-build"
rm -rf "$OUT"
trap 'rm -rf "$OUT"' EXIT

# Optional local-only list of strings that must never appear in the built
# site (employer name, etc). One term per line. Gitignored - never commit.
FORBIDDEN_FILE="$(pwd)/scripts/forbidden-terms.local"

echo "== building =="
if ! "$HUGO" --minify --destination "$OUT" >/dev/null 2>&1; then
  echo "FAIL: hugo build errored"
  "$HUGO" --minify --destination "$OUT" 2>&1 | tail -20
  exit 1
fi

PASS=0
FAIL=0

check() { # check <description> <0-if-ok>
  if [ "$2" -eq 0 ]; then
    echo "  ok   - $1"; PASS=$((PASS+1))
  else
    echo "  FAIL - $1"; FAIL=$((FAIL+1))
  fi
}

present()  { grep -rqFI "$1" "$OUT" >/dev/null 2>&1; }
absent()   { ! grep -rqFI "$1" "$OUT" >/dev/null 2>&1; }

echo "== pages exist =="
check "about page renders"            "$([ -f "$OUT/about/index.html" ]; echo $?)"
check "search page renders"           "$([ -f "$OUT/search/index.html" ]; echo $?)"
check "search index emitted"          "$([ -f "$OUT/index.json" ]; echo $?)"

echo "== contact and identity =="
check "LinkedIn URL present"          "$(present 'linkedin.com/in/angus-dawson-92b035249'; echo $?)"
check "GitHub URL present"            "$(present 'github.com/basil9099'; echo $?)"
check "real name on homepage"         "$(grep -qF 'Angus Dawson' "$OUT/index.html"; echo $?)"

echo "== copy rules (spec: deliberate omissions) =="
MAILTO_HITS="$(grep -rhoIE 'mailto:[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+' "$OUT" 2>/dev/null | grep -viE '\.local$')"
check "no real-domain mailto link"    "$([ -z "$MAILTO_HITS" ]; echo $?)"
check "no personal-domain email"      "$(! grep -rqIiE '[a-z0-9._%+-]+@(hotmail|gmail|outlook|yahoo|icloud)\.[a-z]{2,}' "$OUT"; echo $?)"
if [ -f "$FORBIDDEN_FILE" ]; then
  FORBIDDEN_HIT=0
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    if grep -rqIiF "$term" "$OUT"; then FORBIDDEN_HIT=1; fi
  done < "$FORBIDDEN_FILE"
  check "no forbidden local terms" "$FORBIDDEN_HIT"
else
  echo "  skip - no forbidden-terms file (create scripts/forbidden-terms.local to enable)"
fi
check "no cert-cost language"         "$(! grep -rqIiE 'financial reach|too expensive|afford' "$OUT"; echo $?)"
check "no 'security learner' framing" "$(absent 'security learner'; echo $?)"
check "no 'aspiring' framing"         "$(! grep -rqIi 'aspiring' "$OUT"; echo $?)"

echo "== effects removed =="
check "no scanline overlay"           "$(absent 'repeating-linear-gradient'; echo $?)"
check "no injected ## heading prefix" "$(! grep -rqIE 'content: ?"#{2,3} ?"' "$OUT" >/dev/null 2>&1; echo $?)"

echo "== metadata consistency =="
# Capital-B 'Basil9099' only ever appears as a byline; the GitHub URL is lowercase.
check "no Basil9099 byline"           "$(absent 'Basil9099'; echo $?)"
check "optimum has a real summary"    "$(! grep -qF 'I started with a straightforward service scan' "$OUT/index.html"; echo $?)"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
