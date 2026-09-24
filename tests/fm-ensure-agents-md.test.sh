#!/usr/bin/env bash
# Behavior tests for bin/fm-ensure-agents-md.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-ensure-agents-md)

write_fixture_claude_pointer() {
  cat > "$1/CLAUDE.md" <<'POINTER'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
POINTER
}

assert_no_claude() {
  [ ! -e "$1/CLAUDE.md" ] && [ ! -L "$1/CLAUDE.md" ] || fail "ensure created CLAUDE.md"
}

test_empty_project_creates_only_agents() {
  local repo out
  repo="$TMP_ROOT/empty"
  mkdir -p "$repo"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "empty project ensure failed"
  assert_contains "$out" "created: AGENTS.md" "empty project did not report creation"
  assert_present "$repo/AGENTS.md" "AGENTS.md was not created"
  assert_no_claude "$repo"
  assert_grep '## Maintaining this file' "$repo/AGENTS.md" "skeleton lacks self-governance"
  assert_grep 'Keep this file for knowledge useful to almost every future agent session in this project.' "$repo/AGENTS.md" "skeleton lost the future-session bar"
  assert_grep 'Do not repeat what the codebase already shows; point to the authoritative file or command instead.' "$repo/AGENTS.md" "skeleton lost pointer guidance"
  assert_grep 'Prefer rewriting or pruning existing entries over appending new ones.' "$repo/AGENTS.md" "skeleton lost curation guidance"
  assert_grep 'When updating this file, preserve this bar for all agents and keep entries concise.' "$repo/AGENTS.md" "skeleton lost governance guidance"
  cp "$repo/AGENTS.md" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "empty project re-run failed"
  assert_contains "$out" 'unchanged:' "re-run did not report unchanged"
  cmp -s "$repo/.before" "$repo/AGENTS.md" || fail "re-run changed AGENTS.md"
  assert_no_claude "$repo"
  pass "fm-ensure-agents-md.sh: empty project creates only governed AGENTS.md"
}

test_existing_agents_gains_governance_without_claude() {
  local repo out count
  repo="$TMP_ROOT/existing"
  mkdir -p "$repo"
  printf '# Existing memory\n\nDeploy with kubectl.\n' > "$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "existing AGENTS.md ensure failed"
  assert_contains "$out" 'updated:' "injection did not report update"
  assert_grep 'Deploy with kubectl.' "$repo/AGENTS.md" "existing content was lost"
  count=$(grep -Fc '## Maintaining this file' "$repo/AGENTS.md")
  [ "$count" -eq 1 ] || fail "injection wrote $count governance sections"
  assert_no_claude "$repo"
  pass "fm-ensure-agents-md.sh: existing AGENTS.md gains governance without CLAUDE.md"
}

test_existing_claude_forms_stay_untouched() {
  local repo kind out
  for kind in real pointer symlink wrong-link dangling-link directory; do
    repo="$TMP_ROOT/both-$kind"
    mkdir -p "$repo"
    printf '# Existing memory\n' > "$repo/AGENTS.md"
    case "$kind" in
      real) printf '# Separate Claude memory\n' > "$repo/CLAUDE.md" ;;
      pointer) write_fixture_claude_pointer "$repo" ;;
      symlink) ln -s AGENTS.md "$repo/CLAUDE.md" ;;
      wrong-link) printf 'other\n' > "$repo/OTHER.md"; ln -s OTHER.md "$repo/CLAUDE.md" ;;
      dangling-link) ln -s MISSING.md "$repo/CLAUDE.md" ;;
      directory) mkdir "$repo/CLAUDE.md" ;;
    esac
    case "$kind" in
      real|pointer) cp "$repo/CLAUDE.md" "$repo/.claude-before" ;;
      *-link|symlink) readlink "$repo/CLAUDE.md" > "$repo/.claude-before" ;;
    esac
    out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "ensure failed with $kind CLAUDE.md"
    assert_contains "$out" 'updated:' "governance insertion did not report update ($kind)"
    assert_grep '## Maintaining this file' "$repo/AGENTS.md" "governance missing ($kind)"
    case "$kind" in
      real|pointer) cmp -s "$repo/.claude-before" "$repo/CLAUDE.md" || fail "CLAUDE.md changed ($kind)" ;;
      *-link|symlink) [ -L "$repo/CLAUDE.md" ] || fail "CLAUDE.md link converted ($kind)"; [ "$(cat "$repo/.claude-before")" = "$(readlink "$repo/CLAUDE.md")" ] || fail "CLAUDE.md link retargeted ($kind)" ;;
      directory) [ -d "$repo/CLAUDE.md" ] || fail "CLAUDE.md directory changed" ;;
    esac
    cp "$repo/AGENTS.md" "$repo/.agents-after"
    out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "re-run failed with $kind CLAUDE.md"
    assert_contains "$out" 'unchanged:' "re-run did not report unchanged ($kind)"
    cmp -s "$repo/.agents-after" "$repo/AGENTS.md" || fail "re-run changed AGENTS.md ($kind)"
  done
  pass "fm-ensure-agents-md.sh: existing CLAUDE.md forms stay untouched"
}

test_real_claude_content_is_copied() {
  local repo out
  repo="$TMP_ROOT/promote"
  mkdir -p "$repo"
  printf '# Existing memory\n\nRun tests with make test.' > "$repo/CLAUDE.md"
  cp "$repo/CLAUDE.md" "$repo/.before"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "CLAUDE.md promotion failed"
  assert_contains "$out" 'promoted:' "promotion was not reported"
  cmp -s "$repo/.before" "$repo/CLAUDE.md" || fail "promotion changed CLAUDE.md"
  assert_grep 'Run tests with make test.' "$repo/AGENTS.md" "promotion lost source content"
  assert_grep '## Maintaining this file' "$repo/AGENTS.md" "promotion omitted governance"
  [ -z "$(grep -B1 -Fx '## Maintaining this file' "$repo/AGENTS.md" | head -n 1)" ] || fail "promotion omitted blank separator"
  pass "fm-ensure-agents-md.sh: real CLAUDE.md content is copied and governed"
}

test_legacy_pointer_creates_skeleton_without_changing_pointer() {
  local repo
  repo="$TMP_ROOT/legacy-pointer"
  mkdir -p "$repo"
  write_fixture_claude_pointer "$repo"
  cp "$repo/CLAUDE.md" "$repo/.before"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "legacy pointer ensure failed"
  assert_grep '# Project agent memory' "$repo/AGENTS.md" "pointer was copied as project memory"
  cmp -s "$repo/.before" "$repo/CLAUDE.md" || fail "legacy pointer changed"
  pass "fm-ensure-agents-md.sh: legacy pointer remains untouched"
}

test_only_nonfile_claude_creates_skeleton() {
  local repo kind
  for kind in symlink dangling-link directory; do
    repo="$TMP_ROOT/only-$kind"
    mkdir -p "$repo"
    case "$kind" in
      symlink) ln -s AGENTS.md "$repo/CLAUDE.md" ;;
      dangling-link) ln -s OTHER.md "$repo/CLAUDE.md" ;;
      directory) mkdir "$repo/CLAUDE.md" ;;
    esac
    "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "ensure failed with only $kind CLAUDE.md"
    assert_grep '# Project agent memory' "$repo/AGENTS.md" "skeleton missing with only $kind CLAUDE.md"
    case "$kind" in
      symlink) [ -L "$repo/CLAUDE.md" ] && [ "$(readlink "$repo/CLAUDE.md")" = AGENTS.md ] || fail "AGENTS.md symlink changed" ;;
      dangling-link) [ -L "$repo/CLAUDE.md" ] && [ "$(readlink "$repo/CLAUDE.md")" = OTHER.md ] || fail "dangling symlink changed" ;;
      directory) [ -d "$repo/CLAUDE.md" ] || fail "CLAUDE.md directory changed" ;;
    esac
  done
  pass "fm-ensure-agents-md.sh: nonfile CLAUDE.md stays untouched"
}

test_project_mark_and_crlf_are_preserved() {
  local repo eol out
  for eol in $'\n' $'\r\n'; do
    repo=$(mktemp -d "$TMP_ROOT/marked.XXXXXX")
    printf '%s%s' '<!-- firstmate:maintained-by-project -->' "$eol" '# Project memory' "$eol" '## Editing these notes' "$eol" > "$repo/AGENTS.md"
    cp "$repo/AGENTS.md" "$repo/.before"
    out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1) || fail "marked project ensure failed"
    assert_contains "$out" 'unchanged:' "marked project was changed"
    cmp -s "$repo/.before" "$repo/AGENTS.md" || fail "marked project content changed"
    assert_no_claude "$repo"
  done
  repo="$TMP_ROOT/crlf-injection"
  mkdir -p "$repo"
  printf '# Existing memory\r\n\r\nBuild with make.\r\n' > "$repo/AGENTS.md"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "CRLF injection failed"
  LC_ALL=C grep -Fqx $'## Maintaining this file\r' "$repo/AGENTS.md" || fail "CRLF heading missing"
  cp "$repo/AGENTS.md" "$repo/.before"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1 || fail "CRLF re-run failed"
  cmp -s "$repo/.before" "$repo/AGENTS.md" || fail "CRLF re-run changed AGENTS.md"
  assert_no_claude "$repo"
  pass "fm-ensure-agents-md.sh: project mark and CRLF remain idempotent"
}

test_invalid_agents_names_are_refused() {
  local repo out rc
  repo="$TMP_ROOT/lowercase"
  mkdir -p "$repo"
  printf '# memory\n' > "$repo/agents.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1); rc=$?
  [ "$rc" -ne 0 ] || fail "lowercase agents.md was accepted"
  assert_contains "$out" 'conflict:' "case mismatch did not report conflict"
  assert_absent "$repo/AGENTS.md" "case mismatch created AGENTS.md"
  assert_no_claude "$repo"
  repo="$TMP_ROOT/agents-symlink"
  mkdir -p "$repo"
  printf '# memory\n' > "$repo/payload.md"
  ln -s payload.md "$repo/AGENTS.md"
  out=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo" 2>&1); rc=$?
  [ "$rc" -ne 0 ] || fail "AGENTS.md symlink was accepted"
  assert_contains "$out" 'conflict:' "AGENTS.md symlink did not report conflict"
  [ -L "$repo/AGENTS.md" ] || fail "AGENTS.md symlink changed"
  assert_no_claude "$repo"
  pass "fm-ensure-agents-md.sh: invalid AGENTS.md names are refused"
}

test_empty_project_creates_only_agents
test_existing_agents_gains_governance_without_claude
test_existing_claude_forms_stay_untouched
test_real_claude_content_is_copied
test_legacy_pointer_creates_skeleton_without_changing_pointer
test_only_nonfile_claude_creates_skeleton
test_project_mark_and_crlf_are_preserved
test_invalid_agents_names_are_refused
