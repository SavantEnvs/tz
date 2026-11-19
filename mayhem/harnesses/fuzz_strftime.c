/* Fuzz strftime.c (_fmt/_conv/_yconv: every conversion, %E/%O modifiers, ISO week/year math),
   asctime.c, gmtime_r/localtime_rz (timesub/localsub), and the mktime family's normalization
   of arbitrary struct tm fields (timegm, timeoff, mktime_z -> time2/time2sub/normalize_overflow).
   Input layout: 9 ints (tm_sec..tm_isdst), one long (tm_gmtoff / timeoff offset), one time_t,
   then the strftime format string.
   strftime formats broken-down times the library produced (so tm_wday/tm_yday are consistent,
   as in real callers); the raw fields go to the normalizing functions, which accept any
   values. See mayhem/strftime/known-findings/ for the raw-field strftime overflow. */
#include "tz_api.h"

struct tm *gmtime_r(time_t const *, struct tm *);

static timezone_t zone;

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
  (void)argc; (void)argv;
  zone = tzalloc("EST5EDT,M3.2.0,M11.1.0");   /* fixed, read-only rule-based zone */
  if (!zone)
    abort();
  return 0;
}

int LLVMFuzzerTestOneInput(uint8_t const *data, size_t size)
{
  int f[9];
  long off;
  time_t t;
  size_t hdr = sizeof f + sizeof off + sizeof t;
  if (size < hdr)
    return -1;
  memcpy(f, data, sizeof f);
  memcpy(&off, data + sizeof f, sizeof off);
  memcpy(&t, data + sizeof f + sizeof off, sizeof t);
  char *fmt = malloc(size - hdr + 1);
  if (!fmt)
    abort();
  memcpy(fmt, data + hdr, size - hdr);
  fmt[size - hdr] = '\0';

  char buf[512];
  struct tm tm;

  /* Broken-down times produced by the library from the input time_t. */
  if (localtime_rz(zone, &t, &tm))
    strftime(buf, sizeof buf, fmt, &tm);
  if (gmtime_r(&t, &tm))
    strftime(buf, sizeof buf, fmt, &tm);

  /* Arbitrary fields through the normalizing conversions. */
  struct tm raw;
  memset(&raw, 0, sizeof raw);
  raw.tm_sec = f[0]; raw.tm_min = f[1]; raw.tm_hour = f[2]; raw.tm_mday = f[3];
  raw.tm_mon = f[4]; raw.tm_year = f[5]; raw.tm_wday = f[6]; raw.tm_yday = f[7];
  raw.tm_isdst = f[8];
  raw.tm_gmtoff = off;
  raw.tm_zone = "XYZ";
  asctime(&raw);

  tm = raw;
  if (timegm(&tm) != (time_t)-1)
    strftime(buf, sizeof buf, fmt, &tm);
  tm = raw;
  if (timeoff(&tm, off) != (time_t)-1)
    strftime(buf, sizeof buf, fmt, &tm);
  tm = raw;
  if (mktime_z(zone, &tm) != (time_t)-1)
    strftime(buf, sizeof buf, fmt, &tm);
  free(fmt);
  return 0;
}
