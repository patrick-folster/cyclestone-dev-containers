#!/bin/sh
# mvp-qualification.sh — verify the MVP delivery roadmap, validation checklist,
# and compatibility documentation are complete and internally consistent.
#
# This test runs without a container engine. It checks:
#   - delivery-roadmap.md references all 15 milestones, C1–C10, follow-up
#     releases, and out-of-scope items
#   - validation-checklist.md marks deferred evidence items with owner/deadline
#   - compatibility.md includes the deferred native evidence section
#   - DECISIONS.md includes the MVP security confirmation entry
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

roadmap=docs/architecture/delivery-roadmap.md
checklist=docs/architecture/validation-checklist.md
compat=docs/architecture/compatibility.md
decisions=.cyclestone/DECISIONS.md

test -s "$roadmap" || fail "missing: $roadmap"
test -s "$checklist" || fail "missing: $checklist"
test -s "$compat" || fail "missing: $compat"
test -s "$decisions" || fail "missing: $decisions"

# All 15 milestones must be referenced in the dependency graph table.
for n in 0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014 0015; do
  grep -q "ms-pf-$n" "$roadmap" || fail "delivery roadmap does not reference ms-pf-$n"
done

# Compatibility rows C1 through C10 must appear in the roadmap matrix.
for n in 1 2 3 4 5 6 7 8 9 10; do
  grep -q "| C$n |" "$roadmap" || fail "delivery roadmap does not reference C$n"
done

# Required sections and content.
require_text() { grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"; }

require_text "$roadmap" "Dependency graph"
require_text "$roadmap" "MVP release scope"
require_text "$roadmap" "Follow-up release candidates"
require_text "$roadmap" "Out of scope"
require_text "$roadmap" "Kubernetes"
require_text "$roadmap" "Marketplace"
require_text "$roadmap" "V8"
require_text "$roadmap" "PASS"

# Deferred evidence items in validation-checklist.
require_text "$checklist" "DEFERRED"
require_text "$checklist" "@patrick-folster"
require_text "$checklist" "2026-09-30"
require_text "$checklist" "**PASS — static architecture and implementation checks pass.**"

# Compatibility deferred section.
require_text "$compat" "Deferred native evidence"
require_text "$compat" "2026-09-30"
require_text "$compat" "@patrick-folster"

# Security confirmation decision.
require_text "$decisions" "D-037"
require_text "$decisions" "MVP security default confirmation"
require_text "$decisions" "embeds no credentials"
require_text "$decisions" "default-deny"
require_text "$decisions" "runtime-only"

# Validate roadmap does not contain credential patterns.
if grep -R -n -E '(api[_-]?key\s*=\s*["'"'"'][a-zA-Z0-9]|BEGIN.*PRIVATE KEY|sk-[a-zA-Z0-9]{20})' "$roadmap"; then
  fail 'delivery roadmap contains a credential pattern'
fi

# Validate that no TBD/TODO/FIXME placeholders remain in the new docs.
for f in "$roadmap" "$checklist" "$compat"; do
  if grep -Eq '\b(TBD|TO[ -]?DO|FIXME)\b' "$f"; then
    fail "unresolved placeholder found in $f"
  fi
done

echo "PASS: MVP delivery roadmap, validation checklist, and compatibility documentation are complete"
