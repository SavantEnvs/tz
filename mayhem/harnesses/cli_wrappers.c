/* File-input wrappers around upstream's own CLIs (zic.c / zdump.c compiled with
   -Dmain=zic_main / -Dmain=zdump_main). They give every run a private scratch directory
   under $TMPDIR (removed at exit) so no state is shared between inputs and nothing is
   written outside it. Exactly one of the WRAP_* macros is defined per binary.
     WRAP_ZIC       zic -d <scratch> <input>                       (zone source compiler)
     WRAP_ZIC_LEAP  zic -d <scratch> -L <input> <fixed zone file>  (leap-second file reader)
     WRAP_ZDUMP     zdump -v -c 1900,2100 <absolute input>         (TZif loader + zdump) */
#define _GNU_SOURCE
#include <ftw.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char scratch[PATH_MAX];

static int rm_entry(char const *p, struct stat const *sb, int flag, struct FTW *ftw)
{
  (void)sb; (void)flag; (void)ftw;
  remove(p);
  return 0;
}

static void cleanup(void)
{
  if (scratch[0])
    nftw(scratch, rm_entry, 16, FTW_DEPTH | FTW_PHYS);
}

static void make_scratch(void)
{
  char const *tmp = getenv("TMPDIR");
  if (!tmp || tmp[0] != '/')
    tmp = "/tmp";
  snprintf(scratch, sizeof scratch, "%s/tzfuzz-XXXXXX", tmp);
  if (!mkdtemp(scratch)) {
    perror("mkdtemp");
    exit(2);
  }
  atexit(cleanup);
}

#if defined WRAP_ZIC || defined WRAP_ZIC_LEAP
int zic_main(int, char **);
#else
int zdump_main(int, char **);
#endif

int main(int argc, char **argv)
{
  if (argc != 2) {
    fprintf(stderr, "usage: %s INPUT\n", argv[0]);
    return 2;
  }
  make_scratch();
#if defined WRAP_ZIC
  char out[PATH_MAX];
  snprintf(out, sizeof out, "%s/out", scratch);
  char *av[] = { "zic", "-d", out, argv[1], NULL };
  return zic_main(4, av);
#elif defined WRAP_ZIC_LEAP
  static char const zone[] =
    "Rule\tEU\t1981\tmax\t-\tMar\tlastSun\t 1:00u\t1:00\tS\n"
    "Rule\tEU\t1996\tmax\t-\tOct\tlastSun\t 1:00u\t0\t-\n"
    "Zone\tTest/Leap\t0:00\t-\tGMT\t1970\n"
    "\t\t\t1:00\tEU\tCE%sT\n"
    "Link\tTest/Leap\tTest/LeapLink\n";
  char out[PATH_MAX], zfile[PATH_MAX];
  snprintf(out, sizeof out, "%s/out", scratch);
  snprintf(zfile, sizeof zfile, "%s/zone.zi", scratch);
  FILE *fp = fopen(zfile, "w");
  if (!fp || fputs(zone, fp) == EOF || fclose(fp) != 0) {
    perror(zfile);
    return 2;
  }
  char *av[] = { "zic", "-d", out, "-L", argv[1], zfile, NULL };
  return zic_main(6, av);
#elif defined WRAP_ZDUMP
  /* zdump hands NAME to tzalloc, which reads it as a file only when absolute. */
  char abs[PATH_MAX];
  if (!realpath(argv[1], abs)) {
    perror(argv[1]);
    return 2;
  }
  char *av[] = { "zdump", "-v", "-c", "1900,2100", abs, NULL };
  return zdump_main(5, av);
#else
# error "define one of WRAP_ZIC, WRAP_ZIC_LEAP, WRAP_ZDUMP"
#endif
}
