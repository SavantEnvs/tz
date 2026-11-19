/* Public libtz API (NetBSD-inspired, exported by localtime.c when NETBSD_INSPIRED, the default).
   Declared here by hand: private.h renames/redefines libc names and is not a public header. */
#ifndef TZ_API_H
#define TZ_API_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct state *timezone_t;
timezone_t tzalloc(char const *);
void tzfree(timezone_t);
struct tm *localtime_rz(timezone_t, time_t const *, struct tm *);
time_t mktime_z(timezone_t, struct tm *);
time_t time2posix_z(timezone_t, time_t);
time_t posix2time_z(timezone_t, time_t);
time_t timeoff(struct tm *, long);

/* Drive a loaded zone through the conversion API: localtime_rz, strftime, mktime_z and the
   POSIX <-> leap-second time mappings, at fixed probe times plus one taken from the input. */
static void tz_exercise(timezone_t z, uint8_t const *data, size_t size)
{
  time_t probes[] = {
    (time_t)INT64_MIN, (time_t)-(INT64_C(1) << 59), (time_t)INT32_MIN - 1, (time_t)-1,
    0, 1, 78796800, 915148800, (time_t)INT32_MAX, (time_t)INT32_MAX + 1,
    1700000000, 4102444800, (time_t)(INT64_C(1) << 59), (time_t)INT64_MAX, 0,
  };
  size_t nprobes = sizeof probes / sizeof *probes;
  if (size >= sizeof(time_t))
    memcpy(&probes[nprobes - 1], data + size - sizeof(time_t), sizeof(time_t));
  for (size_t i = 0; i < nprobes; i++) {
    struct tm tm;
    char buf[256];
    time_t t = probes[i];
    if (localtime_rz(z, &t, &tm)) {
      strftime(buf, sizeof buf, "%c %Z %z %G-W%V-%u %j %e %I%p", &tm);
      struct tm copy = tm;
      mktime_z(z, &copy);
      copy = tm;
      copy.tm_isdst = -1;
      copy.tm_mday += 400;
      copy.tm_sec -= 100000;
      mktime_z(z, &copy);
    }
    posix2time_z(z, time2posix_z(z, t));
  }
}
#endif
