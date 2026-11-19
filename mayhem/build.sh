#!/usr/bin/env bash
# mayhem/build.sh — build the tz fuzz targets (sanitized) and the oracle tools (normal flags).
#
# Outputs (all under gitignored directories — upstream's .gitignore ignores every subdirectory):
#   /mayhem/out/fuzz_tzload, fuzz_tzparse, fuzz_strftime     libFuzzer harnesses over libtz
#   /mayhem/out/<fuzzer>-standalone                            run-once reproducers
#   /mayhem/out/zic, zic_leap, zdump                           file-input CLI wrappers (sanitized)
#   /mayhem/build-test/zic, zdump                              upstream CLIs, normal flags (test.sh)
# Re-runnable and offline: plain compiler invocations over the checked-in sources, no fetches.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT="$SRC/out"
FB="$SRC/build-fuzz"
TB="$SRC/build-test"
mkdir -p "$OUT" "$FB" "$TB"

# Generated headers the Makefile would write (version.h from `git describe`, tzdir.h from
# TZDIR/TZDEFAULT). Written here directly so the build needs neither git nor make; both
# names are gitignored upstream. TZDIR/TZDEFAULT point at a directory that never exists,
# so no target ever reads the host's /usr/share/zoneinfo: a relative zone name always
# falls through to the POSIX TZ string parser.
printf '%s\n' 'static char const PKGVERSION[]="(tz) ";' \
  'static char const TZVERSION[]="mayhem";' \
  'static char const REPORT_BUGS_TO[]="tz@iana.org";' > version.h
printf '%s\n' '#ifndef TZDEFAULT' '# define TZDEFAULT "/nonexistent-tzdir/localtime"' '#endif' \
  '#ifndef TZDIR' '# define TZDIR "/nonexistent-tzdir"' '#endif' > tzdir.h

# NETBSD_INSPIRED exports tzalloc/localtime_rz/mktime_z; STD_INSPIRED (a documented Makefile
# option) exports timeoff/time2posix/posix2time, which the harnesses also reach.
DEFS="-DNETBSD_INSPIRED=1 -DSTD_INSPIRED=1 -I$SRC"
LIBSRCS="localtime asctime difftime strftime"

# 1) Oracle build: upstream zic and zdump with normal flags (no sanitizers).
for f in zic zdump $LIBSRCS; do
  $CC -O2 $COVERAGE_FLAGS $DEFS -c "$f.c" -o "$TB/$f.o"
done
$CC $COVERAGE_FLAGS -o "$TB/zic" "$TB/zic.o"
$CC $COVERAGE_FLAGS -o "$TB/zdump" "$TB/zdump.o" "$TB/localtime.o" "$TB/strftime.o"

# 2) Sanitized library objects with SanCov for the libFuzzer harnesses.
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1"
$CC $FUZZ_CFLAGS -c mayhem/lsan_off.c -o "$FB/lsan_off.o"
for f in $LIBSRCS; do
  $CC $FUZZ_CFLAGS -fsanitize=fuzzer-no-link $DEFS -c "$f.c" -o "$FB/$f.cov.o"
done
LIBCOV="$FB/localtime.cov.o $FB/asctime.cov.o $FB/difftime.cov.o $FB/strftime.cov.o"
for h in fuzz_tzload fuzz_tzparse fuzz_strftime; do
  $CC $FUZZ_CFLAGS -c "mayhem/harnesses/$h.c" -o "$FB/$h.o"
  $CC $FUZZ_CFLAGS $LIB_FUZZING_ENGINE "$FB/$h.o" $LIBCOV "$FB/lsan_off.o" -o "$OUT/$h"
  $CC $FUZZ_CFLAGS "$STANDALONE_FUZZ_MAIN" "$FB/$h.o" $LIBCOV "$FB/lsan_off.o" -o "$OUT/$h-standalone"
done

# 3) Sanitized file-input CLI targets: upstream zic.c / zdump.c with main renamed, driven by
#    mayhem/harnesses/cli_wrappers.c (private scratch dir per run).
for f in $LIBSRCS; do
  $CC $FUZZ_CFLAGS $DEFS -c "$f.c" -o "$FB/$f.o"
done
$CC $FUZZ_CFLAGS $DEFS -Dmain=zic_main -c zic.c -o "$FB/zic.o"
$CC $FUZZ_CFLAGS $DEFS -Dmain=zdump_main -c zdump.c -o "$FB/zdump.o"
for w in ZIC ZIC_LEAP ZDUMP; do
  $CC $FUZZ_CFLAGS -DWRAP_$w -c mayhem/harnesses/cli_wrappers.c -o "$FB/wrap_$w.o"
done
$CC $FUZZ_CFLAGS -o "$OUT/zic" "$FB/wrap_ZIC.o" "$FB/zic.o" "$FB/lsan_off.o"
$CC $FUZZ_CFLAGS -o "$OUT/zic_leap" "$FB/wrap_ZIC_LEAP.o" "$FB/zic.o" "$FB/lsan_off.o"
$CC $FUZZ_CFLAGS -o "$OUT/zdump" "$FB/wrap_ZDUMP.o" "$FB/zdump.o" "$FB/localtime.o" \
  "$FB/strftime.o" "$FB/lsan_off.o"

ls -l "$OUT" "$TB/zic" "$TB/zdump"
