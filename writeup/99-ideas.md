
-   Measure `fork`.
-   Write a custom launcher; make more syscalls directly
    -   Directly `perf_event_open(2)?
        Make the syscall / buffer myself, trace across multiple CPUs?
        https://github.com/AlexGustafsson/perf
    -   Use `taskset(1)` (`sched_setaffinity(2)` syscall- or is that the C
        function?) so
        we can run in parallel, up to e.g. half the cores... get more results
        faster.
    -   Use `no_std` rust and statically link (may not even need `alloc`?)
        so we don't get any of that noise. :)

        This is always a fun little effort... https://doc.rust-lang.org/core/
        says ~how to do so.

