/* Fuzz the POSIX TZ string parser: tzalloc(<TZ string>) -> tzload fails (TZDIR is built to a
   nonexistent directory) -> tzparse (getzname/getqzname, getoffset, getrule, transtime),
   then the conversion API over the rule-based zone. */
#include "tz_api.h"

int LLVMFuzzerTestOneInput(uint8_t const *data, size_t size)
{
  char *s = malloc(size + 1);
  if (!s)
    abort();
  memcpy(s, data, size);
  s[size] = '\0';
  /* newtzset.3: a TZ value that begins with '/' (optionally after ':') is an absolute file
     name, not a TZ string; that is the TZif loader's surface (fuzz_tzload), so skip it. */
  if (s[0] == '/' || (s[0] == ':' && s[1] == '/')) {
    free(s);
    return -1;
  }
  timezone_t z = tzalloc(s);
  free(s);
  if (!z)
    return -1;
  tz_exercise(z, data, size);
  tzfree(z);
  return 0;
}
