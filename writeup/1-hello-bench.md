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
think for this case, we want to use **`perf` for timing information** and **strace for understanding**.

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

Then, it's "just" some processing and formatting to get data!

[page-cache]: <!-- TODO explain -->

### Subjects

I've written this up for 8 cases, so far:

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


