// C program to clear page cache.
// Amenable to setuid!
//
// See https://www.kernel.org/doc/Documentation/sysctl/vm.txt for documentation
// on the drop_caches file.

#include <fcntl.h>
#include <unistd.h>

int main() {
  int cachefile = open("/proc/sys/vm/drop_caches", O_WRONLY);
  if(cachefile < 0) {
    return cachefile;
  }
  int written = write(cachefile, "1", 1);
  if(written != 1) {
    return -1;
  }
  return 0;
}

