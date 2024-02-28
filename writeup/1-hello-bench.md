# Startup Showdown: Hello

author: "Charles Eckman <charles@cceckman.com>"
date: 2024-02-25

---

What's the baseline startup cost for programs in different languages?
To kick off the [startup showdown](0-outline.md), let's write "hello world"
in different ways, and see what program(s) get to their output first.

## What comes before "Hello"? {#intro}

The classic <!-- TODO: Where did hello, world come from? --> "hello world"
program is the first you'll see in a lot of languages. As it turns out, it's
also a really nice way to measure how long a program takes to get to "our code"!

I know some stuff about program startup; I'l write more about how
it works for various languages in a later post.
<!-- TODO: Link to chapter 4 -->
For now, we just think of it like this:

1.  Some other program makes a [system call] to say, "please start this other
    program"
2.  The kernel loads "that other program", and switches control to it
3.  The _runtime_ of the program starts, and prepares to run the code we wrote
4.  Our code runs!

[system call]: <!-- TODO -->

The "cost" I want to measure is the combination of (2) and (3). A program can
embody choices that make (2) or (3) more or less expensive.

The neat thing about "hello, world" programs is that
**steps 1 and 4 are really easy to see**.
Both of them are system calls: step (1) is some flavor of `exec`, and
step (4) is some flavor of `write`.

If we can get good times on (1) and (4), we can take their difference as
"the startup time". Done!

## Peeking at system calls

There's a bunch of different tools that can help us look at system calls!
The most obvious is a debugger like `gdb` or `lldb`, but there's also `strace`
and `perf`.

I'm still learning about all of these tools (there's a lot to learn!). I
think for this case, we want to use **`perf` for timing information** and
**`strace` for understanding**.

<!-- TODO : Extract this to a tangent, and run the numbers on timing -->

### `strace` and `ptrace`

One tool I know about is `strace`. It runs a program, and streams out all the
system calls that the program makes, and the arguments to those system calls.
Cool!

For example: here's the first few lines of `strace` tracing `true`:

```shell
∵ strace true 2>&1 | head -5
execve("/usr/bin/true", ["true"], 0x7ffefe7c67c0 /* 45 vars */) = 0
brk(NULL)                               = 0x55d3a6dd6000
mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6344a44000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
```

And for more fun, here's `strace` tracing `strace` tracing `true`:

```shell
∵ strace strace -o /dev/null true 2>&1 | head -5
execve("/usr/bin/strace", ["strace", "-o", "/dev/null", "true"], 0x7ffe9926ff48 /* 45 vars */) = 0
brk(NULL)                               = 0x55c7c2419000
mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fdce7536000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
```

`strace` uses the `ptrace` system calls to do this:

```shell
∵ strace strace -o /dev/null true 2>&1 | grep ptrace | head -5
openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libunwind-ptrace.so.0", O_RDONLY|O_CLOEXEC) = 3
ptrace(PTRACE_SEIZE, 55678, NULL, 0)    = 0
ptrace(PTRACE_SETOPTIONS, 55679, NULL, PTRACE_O_TRACESYSGOOD) = 0
ptrace(PTRACE_GET_SYSCALL_INFO, 55679, 88, {op=PTRACE_SYSCALL_INFO_NONE, arch=AUDIT_ARCH_X86_64, instruction_pointer=0x7f035c4be267, stack_pointer=0x7ffcd5d9c3f8}) = 24
ptrace(PTRACE_SYSCALL, 55679, NULL, 0)  = 0
```

What's `ptrace`?  On my system, `man 2 ptrace` provides a decent summary at the top:

> The **ptrace()** system call provides a means by which one process (the "tracer") may observe and control the execution of another process (the "tracee"), and examine and change the tracee's memory and registers. It is primarily used to implement breakpoint debugging and system call tracing.

"system call tracing" is what we're looking for- but I'm not sure a `ptrace`-based tool is quite what we want.

I've used `ptrace` directly before, for doing something a little like [Wine]:
running a program "not for Linux" under Linux, by intercepting all system calls.
The way `ptrace` works is:

1.  Tracer "attaches" to tracee
2.  Whenever the tracee makes a system call or receives a [signal], the kernel
    stops the tracee and switches to the tracer.
3.  Then the tracer can poke at the tracee's memory or registers. The tracer can
    replace or bypass the system call / signal on the tracee's behalf.
4.  Once the tracer is done with "whatever", it tells the kernel how to
    continue, which may allow the tracee to resume.

[Wine]: https://www.winehq.org/
[signal]: <!-- TOOD -->

This is **great for understanding**! `strace` tells us things like
"the path passed to this `open` call" - what we need to understand what the
system call is doing. Julia Evans has a [nice roundup](https://jvns.ca/blog/2021/04/03/what-problems-do-people-solve-with-strace/)
of problems that `strace` can solve!

But this kind of tracing **changes the performance of the program**. We aren't
seeing how long it takes for the tracee to complete - we're also seeing how long
the tracer takes to say "go ahead".

What other options do we have?

### `perf`

I learned a lot about `perf` from [this zine](https://wizardzines.com/zines/perf/),
and there's more info at [Brendan Gregg's site](https://www.brendangregg.com/perf.html).

The Linux kernel has a whole system for different kinds of performance
monitoring- [profiling, tracing, and counting][kinds]; there's a useful tool
that interacts with it called `perf`. One of the events (event types) that can
be traced is system calls!

When enabled, the kernel will log system calls into an in-memory buffer,
then the `perf` (or other) program can read them out. Unlike `strace`, the
"tracer" sees the system call after the fact- the kernel doesn't wait until the
event is seen by the tracer to service it. This means **`perf trace` has very
low performance cost** compared to `ptrace`- there's no waiting for another
user program.

(At least, in theory - I haven't measured these!)

The drawback is that `perf` doesn't capture process-level details of the system
calls. Look at what `strace` and `perf` show for a shell running `echo hi`:

```shell
∵ strace sh -c 'echo hi >/dev/null' 2>&1 | grep write
write(1, "hi\n", 3)                     = 3
∵ sudo perf trace sh -c 'echo hi >/dev/null'  2>&1 | grep write
     0.294 ( 0.001 ms): sh/56499 write(fd: 1, buf: 0x55808bc98780, count: 3)                           = 3
```

`strace` has shown us the string, while `perf` has just recorded the pointer.

In my opinion- at least, without additional configuration- `perf` will be less
good for **understanding what a program is doing**, e.g. for debugging.

[kinds]: <!-- TODO - say more about different kinds of collection. jvns' zine calls out that _events_ mean _profiling_ is not done, which I learned today -->

## Procedure

We'll make "a hello world program" in a bunch of different languages. For this
experiment, we're going to say "a hello world program" is:

-   A file
-   Executable by my Linux install (`+x` and in a format Linux understands)
-   That prints the string `Hello, world!\n` to its output

This lines up with my [original question](0-outline.md#original)- we're going to
invoke every one as `./test`, regardless of language.

To time the program, we'll run it under `perf record`. We can look at the
time from [steps (1) from (4)](#intro) by filtering down to the right system
calls, and write to a file for later analysis:

```
perf record \
    --output="/tmp/perf.out" \
    --event="syscalls:sys_exit_execve,syscalls:sys_enter_write" \
    ./my-test-binary
```

We'll do two sets of runs for each program.

-   One run will simulate a frequently / recently-used program: just run
    the program repeatedly.

-   Another run will simulate an infrequently / not-recently-used program:
    [clear the page cache][page-cache] between runs.

Then it's "just" some processing and

[page-cache]: <!-- TODO explain -->

### Subjects

I've written up 8 "hello" programs:

1.  Shell script
    1.  `#!/usr/bin/dash`, the [Debian Alquist Shell](https://wiki.archlinux.org/title/Dash), designed to be a minimal POSIX-compliant shell
    2.  `#!/usr/bin/bash`, the Bourne Again Shell, a common default shell
    3.  `#!/usr/bin/zsh`, the Z Shell, the shell I use
2.  Python
3.  C-like: compiled to machine code, backed by `libc`
    1.  C
    2.  C++
    3.  Rust
4.  Golang (...which does not depend on `libc` by default)

All programs are built an run in "as default a manner" as possible- e.g. without
(non-default) optimizations applied, without additional link flags, etc.

## The results

I'll present my results here, but **you can run this yourself!!**
The code is in [repository](https://github.com/cceckman/startup-showdown),
including the orchestrator. If you have the compilers/interpreters installed[^prereqs],
you can download and run `./do` and get all the results yourself!

(At least, as of commit 8fef593...)

Aggregates of the data, with numeric values in seconds:

mode     | sut      | mean   | median | min    | max
---------|----------|--------|--------|--------|-----
base     | 5-c      | 0.0005 | 0.0005 | 0.0005 | 0.0005
base     | 1-dash   | 0.0006 | 0.0006 | 0.0006 | 0.0006
base     | 7-rust   | 0.0007 | 0.0007 | 0.0007 | 0.0008
base     | 2-bash   | 0.0013 | 0.0013 | 0.0013 | 0.0013
base     | 6-cpp    | 0.0014 | 0.0014 | 0.0014 | 0.0014
base     | 3-zsh    | 0.0018 | 0.0018 | 0.0018 | 0.0019
base     | 8-golang | 0.0032 | 0.0032 | 0.0023 | 0.0041
base     | 4-python | 0.0182 | 0.0141 | 0.014  | 0.0556
no_cache | 5-c      | 0.0005 | 0.0005 | 0.0005 | 0.0005
no_cache | 1-dash   | 0.0006 | 0.0006 | 0.0006 | 0.0009
no_cache | 7-rust   | 0.0011 | 0.0011 | 0.001  | 0.0012
no_cache | 6-cpp    | 0.0015 | 0.0015 | 0.0014 | 0.0016
no_cache | 3-zsh    | 0.0026 | 0.0023 | 0.0023 | 0.0036
no_cache | 2-bash   | 0.0038 | 0.003  | 0.0029 | 0.0086
no_cache | 8-golang | 0.006  | 0.0057 | 0.0041 | 0.0099
no_cache | 4-python | 0.0263 | 0.0224 | 0.0221 | 0.0562

And the [raw data](1-hello-bench/aggregate.csv). This is in a Debian Linux VM
on a server-type machine, but I'm not going to go into all the specs. If your results
are different - that's interesting! Why is that?

[^prereq]: The prerequisites are: `clang` and `clang++` for C and C++; `cargo` for Rust; `python3` for Python; `zsh`, `bash`, and `dash` for the shells.

### What's wrong with this picture?

I know there's some issues with this test setup that show up in the results,
so let me call them out before going further.

#### `no_cache` doesn't mean anything for `dash` {#dash}

I'm making `no_cache` happen by writing to `/proc/sys/vm/drop_caches`
(documentation provided by [the Linux kernel](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)). This is meant to get rid of any files that might be hanging
around in memory that aren't actively in use, simulating the case where
"I haven't run this program in a while".

This has some effect...but not a lot. At least for `dash`, we can explain why.

The test runner I'm using is `./do`, the
[minimal version](https://github.com/apenwarr/redo/tree/main/minimal)
of Avery Pennarun's [redo](https://github.com/apenwarr/redo). Which uses the
system shell:

```
$ head -1 ./do
#!/usr/bin/env sh
```

So I'm pretty sure the `dash` program itself will still be in memory when we
get to that test- it's re-invoked between when we dump the page cache and when
we run the test program, so our test fixture gets the "load the interpreter"
penalty.

(Still - almost as fast as C? Nice job, `dash` authors!)

#### `no_cache` doesn't mean _much_ for `libc` programs {#libc}

Similarly: I think all of these (except Go) wind up using the same `libc.so`,
which will esentially just live in my computer's memory. That's a chunk of code
that I don't think `no_cache` wipes - so it gives Golang more of a penalty.

### Observations

**C is fast!** Not surprising, but it's useful to validate. [For future
investigation](0-outline.md) - how much of that is because [`libc` is already in
memory?](#libc)

**`dash` is almost as fast as C!** Even given the [above](#dash) observation on
residency, I'm still impressed that it can parse & complete the script before
a compiled program.

**Go is takes longer than I expected!** I'll want to analyze Go startup more in
a future post <!-- TODO -->, but I was surprised by how long it took.
This is a program with no `go` keyword, no networking...no stack escapes, I think?
And no dynamic linking! But it still takes ~an order of magnitude longer.

**All of these are very fast!** 60fps video is $ 1000 / 60 = 16.66... $
milliseconds per frame; Python is the only one of these that would have trouble
_starting a new process every frame_ and keeping up... at least, as far as
the program itself goes.

## Improvements and further experiments

I had some next [outlined](0-outline.md), but thinking about these results
has given me some new ones to think about!

There's `perf` counters and events we could dig into to see _what_ is causing
the penalties for these. For instance, the `no_cache` differences - which
programs are loading more / less from disk?

How much does a shared `libc` help? What would these look like with a static `libc`?

This is the cost "in the process", after `exec`; what's the _kernel_'s
contribution?

## Let me know what you think!

I'm planning on posting [more in this series](0-outline.md), so check back!

If you have answers, more questions, or suggestions, [reach out](https://cceckman.com)!

