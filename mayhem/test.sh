#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer functional oracle for tz (zic + zdump, built by build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Known-answer probes through the upstream zic + zdump built by build.sh with normal flags
# (build-test/). Each probe compiles real tz data / hand-written sources and asserts exact
# zdump output lines (well-known DST transitions, a leap second, link identity, zic's
# rejection of bad input). A missing binary is a failure, never a skip.
TB="$SRC/build-test"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tz-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
passed=0 failed=0
ok()   { passed=$((passed+1)); echo "PASS: $1"; }
bad()  { failed=$((failed+1)); echo "FAIL: $1"; }
for b in zic zdump; do [ -x "$TB/$b" ] || { echo "missing $TB/$b — build.sh did not build it" >&2; emit_ctrf tz-kat 0 1; exit 1; }; done

# expect_line <name> <haystack> <exact line>
expect_line() { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok "$1"; else bad "$1 (wanted: $3)"; fi; }
# expect_sub <name> <haystack> <substring>
expect_sub()  { if printf '%s\n' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (wanted: $3)"; fi; }

# 1) zic compiles upstream's europe + northamerica data.
if "$TB/zic" -d "$WORK/zi" "$SRC/europe" "$SRC/northamerica" && [ -s "$WORK/zi/Europe/Berlin" ]; then
  ok "zic compiles europe+northamerica"; else bad "zic compiles europe+northamerica"; fi
# The compiled file starts with the TZif magic and is version 2+.
magic="$(head -c 5 "$WORK/zi/Europe/Berlin" 2>/dev/null | od -An -c | tr -d ' ')"
case "$magic" in TZif2|TZif3|TZif4) ok "TZif magic/version ($magic)";; *) bad "TZif magic/version (got '$magic')";; esac

# 2) Europe/Berlin 2020 spring-forward and fall-back.
out="$("$TB/zdump" -v -c 2020,2021 "$WORK/zi/Europe/Berlin" 2>&1)"
Z="$WORK/zi/Europe/Berlin"
expect_line "Berlin CEST start" "$out" "$Z  Sun Mar 29 01:00:00 2020 UT = Sun Mar 29 03:00:00 2020 CEST isdst=1 gmtoff=7200"
expect_line "Berlin CEST end"   "$out" "$Z  Sun Oct 25 01:00:00 2020 UT = Sun Oct 25 02:00:00 2020 CET isdst=0 gmtoff=3600"

# 3) America/New_York 2023.
out="$("$TB/zdump" -v -c 2023,2024 "$WORK/zi/America/New_York" 2>&1)"
Z="$WORK/zi/America/New_York"
expect_line "New_York EDT start" "$out" "$Z  Sun Mar 12 07:00:00 2023 UT = Sun Mar 12 03:00:00 2023 EDT isdst=1 gmtoff=-14400"
expect_line "New_York EDT end"   "$out" "$Z  Sun Nov  5 06:00:00 2023 UT = Sun Nov  5 01:00:00 2023 EST isdst=0 gmtoff=-18000"

# 4) POSIX TZ string parsed by tzparse (TZDIR is a nonexistent dir, so no file lookup).
#    Weekday omitted on the local side: upstream HEAD currently mis-reports tm_wday for
#    TZ-string-only zones, and this oracle must not depend on that.
out="$("$TB/zdump" -v -c 2023,2024 'EST5EDT,M3.2.0,M11.1.0' 2>&1)"
expect_sub "TZ string EDT start" "$out" "Sun Mar 12 07:00:00 2023 UT = "
expect_sub "TZ string EDT local" "$out" "Mar 12 03:00:00 2023 EDT isdst=1 gmtoff=-14400"
out="$("$TB/zdump" -v -c 2023,2024 '<-03>3<-02>,M3.5.0/-2,M10.5.0/-1' 2>&1)"
expect_sub "TZ string negative rule times" "$out" "Sun Mar 26 01:00:00 2023 UT = "
expect_sub "TZ string numeric abbrev" "$out" "Mar 25 23:00:00 2023 -02 isdst=1 gmtoff=-7200"

# 5) Leap seconds (-L) and Link handling.
printf 'Leap\t2016\tDec\t31\t23:59:60\t+\tS\n' > "$WORK/leap"
printf 'Zone\tEtc/UTC\t0\t-\tUTC\nLink\tEtc/UTC\tTest/Alias\n' > "$WORK/utc.zi"
if "$TB/zic" -d "$WORK/lz" -L "$WORK/leap" "$WORK/utc.zi"; then ok "zic -L"; else bad "zic -L"; fi
out="$("$TB/zdump" -v -c 2016,2018 "$WORK/lz/Etc/UTC" 2>&1)"
expect_line "leap second 23:59:60" "$out" "$WORK/lz/Etc/UTC  Sun Jan  1 00:00:00 2017 UT = Sat Dec 31 23:59:60 2016 UTC isdst=0 gmtoff=0"
if [ -s "$WORK/lz/Test/Alias" ] && cmp -s "$WORK/lz/Etc/UTC" "$WORK/lz/Test/Alias"; then ok "Link target identical"; else bad "Link target identical"; fi

# 6) zic rejects malformed input with a diagnostic and non-zero status.
printf 'Bogus line\n' > "$WORK/bad.zi"
msg="$("$TB/zic" -d "$WORK/bz" "$WORK/bad.zi" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$msg" | grep -qF 'input line of unknown type'; then ok "zic rejects bad line"; else bad "zic rejects bad line (rc=$rc: $msg)"; fi

emit_ctrf tz-kat "$passed" "$failed" 0
