/* Fuzz the TZif binary loader: tzalloc(<absolute file name>) -> tzload -> tzloadbody
   (header, transitions, types, leap seconds, footer TZ string -> tzparse), then the
   conversion API over the loaded zone. tzalloc takes a file name, so the input is staged
   in a private mkstemp file under $TMPDIR (removed before returning). */
#include <stdio.h>
#include <unistd.h>
#include "tz_api.h"

int LLVMFuzzerTestOneInput(uint8_t const *data, size_t size)
{
  char const *tmp = getenv("TMPDIR");
  char path[4096];
  if (!tmp || tmp[0] != '/')
    tmp = "/tmp";   /* tzload reads NAME as a file only when it is absolute (tzfile.5/newtzset.3) */
  snprintf(path, sizeof path, "%s/tzload-XXXXXX", tmp);
  int fd = mkstemp(path);
  if (fd < 0)
    abort();
  size_t off = 0;
  while (off < size) {
    ssize_t w = write(fd, data + off, size - off);
    if (w <= 0)
      abort();
    off += (size_t)w;
  }
  close(fd);
  timezone_t z = tzalloc(path);
  unlink(path);
  if (!z)
    return -1;   /* the loader rejected the file */
  tz_exercise(z, data, size);
  tzfree(z);
  return 0;
}
