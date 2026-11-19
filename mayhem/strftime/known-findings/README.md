# Known finding: signed overflow in strftime ISO-week math (found while integrating)

`strftime.c` `_fmt`, case `'V'`/`'G'`/`'g'` (line ~472 at upstream 84585da3):

    bot = ((yday + 11 - wday) % DAYSPERWEEK) - 3;

`yday`/`wday` are copied unchecked from the caller's `struct tm`. With out-of-range values
(e.g. `tm_yday = -1644167157`, `tm_wday = 1409286144`) the subtraction overflows `int`:

    strftime.c:472:25: runtime error: signed integer overflow: -1371340789 - 2017591296 cannot be represented in type 'int'

C17 7.27.3.5 says out-of-range fields make the *output characters* unspecified, not the
behavior undefined, so this is an upstream bug (CWE-190), low impact. Reproduce:

    struct tm tm = {0}; tm.tm_yday = -1644167157; tm.tm_wday = 1409286144;
    char buf[64]; strftime(buf, sizeof buf, "%V", &tm);   /* built with -fsanitize=undefined */

Fix: reduce `yday`/`wday` modulo DAYSPERWEEK (or compute in a wider type) before combining.

The `strftime` target formats broken-down times the library itself produced (localtime_rz,
gmtime_r, normalized mktime_z/timegm results), so it does not re-hit this on every run.
