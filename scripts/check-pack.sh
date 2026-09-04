#!/usr/bin/env bash
# check-pack.sh — validates the trust posture of sui-move-security-skills.
#
# For every skills/*/SKILL.md:
#   - frontmatter (the block between the first two '---' lines) is present
#   - frontmatter declares name, description, allowed-tools
#   - the file contains no curl, wget, sh -c, or other network fetch
#
# Exits 0 and prints counts if every SKILL.md found passes every check.
# Exits 1 and lists every failure otherwise. Read-only: touches nothing.
set -uo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$PACK_ROOT/skills"

total=0
checked=0
failed=0
declare -a failures=()

# Patterns that indicate a network fetch or a shell-out to a remote source.
# Matched case-insensitively against the whole file body (frontmatter and prose).
NETWORK_PATTERNS='curl|wget|http\.get|fetch\(|urllib|requests\.get|sh -c|nc -e|/dev/tcp/'

for f in "$SKILLS_DIR"/*/SKILL.md; do
  [ -e "$f" ] || continue
  total=$((total + 1))
  name="$(basename "$(dirname "$f")")"
  site_failed=0

  # --- frontmatter presence: exactly two '---' delimiter lines at top ---
  first_line="$(head -n1 "$f")"
  if [ "$first_line" != "---" ]; then
    failures+=("$name: SKILL.md does not open with '---' frontmatter delimiter")
    site_failed=1
  else
    fm="$(awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$f")"
    if [ -z "$fm" ]; then
      failures+=("$name: no frontmatter block found between '---' delimiters")
      site_failed=1
    fi
    for field in name description allowed-tools; do
      if ! printf '%s\n' "$fm" | grep -qE "^${field}:"; then
        failures+=("$name: frontmatter missing required field '${field}'")
        site_failed=1
      fi
    done
  fi

  # --- no shell fetches / network calls anywhere in the file ---
  hits="$(grep -inE "$NETWORK_PATTERNS" "$f" || true)"
  if [ -n "$hits" ]; then
    while IFS= read -r line; do
      failures+=("$name: forbidden network/shell-fetch pattern — $line")
    done <<< "$hits"
    site_failed=1
  fi

  if [ "$site_failed" -eq 0 ]; then
    checked=$((checked + 1))
  else
    failed=$((failed + 1))
  fi
done

echo "sui-move-security-skills — check-pack.sh"
echo "SKILL.md files found:  $total"
echo "passed clean:          $checked"
echo "failed:                $failed"

if [ "$failed" -gt 0 ]; then
  echo
  echo "Failures:"
  for line in "${failures[@]}"; do
    echo "  - $line"
  done
  exit 1
fi

exit 0
