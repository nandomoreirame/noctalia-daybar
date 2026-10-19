#!/usr/bin/env bash
# Static guards over plugin code (root *.luau, lib/, views/). The test harness is exempt.
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mapfile -t files < <(find . -maxdepth 1 -name '*.luau'; find lib views -name '*.luau' 2>/dev/null)
fail=0
if ((${#files[@]})); then
  if grep -nE '\b(loadstring|getfenv|setfenv)\b|(^|[^.:A-Za-z_])load[[:space:]]*\(' "${files[@]}"; then
    echo "guards: dynamic code evaluation is forbidden" >&2; fail=1
  fi
  if grep -nE 'noctalia\.(runAsync|runStream|runInTerminal)\([[:space:]]*["'"'"'[]' "${files[@]}"; then
    echo "guards: external commands must be argv tables" >&2; fail=1
  fi
fi
if grep -rniE 'n[i]ko' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.generated . >/dev/null; then
  echo "guards: reference to a previous project found" >&2; fail=1
fi
((fail == 0)) && echo "guards: ok"
exit "$fail"
