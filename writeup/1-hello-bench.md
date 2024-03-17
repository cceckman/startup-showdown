---
author: "Charles Eckman <charles@cceckman.com>"
date: 2024-03-17
---

# Startup Showdown: Hello

To kick off the [startup showdown](0-outline.md), let's write "hello world"
in several languages, and see what program(s) get to their output first.

## What comes before "Hello"? {#intro}

The classic <!-- TODO: Where did hello, world come from? --> "hello world"
program is the first you'll see in a lot of languages. As it turns out, it's
also a really nice way to measure how long a program takes to get to "our code"!

I'll write more about how program startup works in [a later post](0-outline.md).
<!-- TODO: Link to chapter 4 -->
For now, I'm working with this model:

1.  Some program makes a system call, "please start this other program"
2.  The kernel loads the new program, and switches control to it
3.  The _runtime_ for the new program's language starts, and prepares to run
    the code we wrote
4.  Our code runs!

The "cost" I want to measure is the combination of (2) and (3). Depending
on what language we chose, and other choices we make in preparing the program,
those steps might be more or less costly.

The neat thing about "hello, world" is that
**steps 1 and 4 are really easy to see**.
Both of them are system calls: step (1) is some flavor of `exec`, and
step (4) is some flavor of `write`.

If we can get good times on (1) and (4), we can consider their difference to
be "the startup time". Done!

## Peeking at system calls

We have a lots of tools we can use to look at system calls!
For some things we might use a debugger like `gdb` or `lldb`, but there's also
`strace` and `perf`.

I'm still learning about all of these tools (there's a lot to learn!)
I think for this case, I want to use **`perf` for timing information**.
I'll use `strace` later to better understand what's going on.

Why? Read on!

<!-- TODO : Extract this to a tangent, and run the numbers on timing -->

### `strace` and `ptrace`

`strace` runs a program and tells you all the system calls that the program
makes, and the arguments to those system calls. Cool!

I've used this in the past when debugging unknown programs, or to better
understand how a program interacts with the system without wanting to debug
the program itself.

Here's the first few lines of `strace` tracing `true`:

```shell
∵ strace true 2>&1 | head -5
execve("/usr/bin/true", ["true"], 0x7ffefe7c67c0 /* 45 vars */) = 0
brk(NULL)                               = 0x55d3a6dd6000
mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6344a44000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
```

And for more fun, here's a snippet of `strace` tracing `strace` tracing `true`:

```shell
∵ strace strace -o /dev/null true 2>&1 | head -100 | tail -5
wait4(60084, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTRAP | 0x80}], 0, NULL) = 60084
ptrace(PTRACE_GET_SYSCALL_INFO, 60084, 88, {op=PTRACE_SYSCALL_INFO_ENTRY, arch=AUDIT_ARCH_X86_64, instruction_pointer=0x7f8107a4e719, stack_pointer=0x7fffacc41b48, entry={nr=__NR_chdir, args=[0x5577a886bc81, 0xbad1fed1, 0xbad2fed2, 0xbad3fed3, 0xbad4fed4, 0xbad5fed5]}}) = 80
ptrace(PTRACE_SYSCALL, 60084, NULL, 0)  = 0
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_TRAPPED, si_pid=60084, si_uid=1000, si_status=SIGTRAP, si_utime=0, si_stime=0} ---
wait4(60084, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTRAP | 0x80}], 0, NULL) = 60084
```

`strace` uses `ptrace` system calls to do its job.

```shell
∵ strace strace -o /dev/null true 2>&1 | grep ptrace | head -5
openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libunwind-ptrace.so.0", O_RDONLY|O_CLOEXEC) = 3
ptrace(PTRACE_SEIZE, 55678, NULL, 0)    = 0
ptrace(PTRACE_SETOPTIONS, 55679, NULL, PTRACE_O_TRACESYSGOOD) = 0
ptrace(PTRACE_GET_SYSCALL_INFO, 55679, 88, {op=PTRACE_SYSCALL_INFO_NONE, arch=AUDIT_ARCH_X86_64, instruction_pointer=0x7f035c4be267, stack_pointer=0x7ffcd5d9c3f8}) = 24
ptrace(PTRACE_SYSCALL, 55679, NULL, 0)  = 0
```

What's `ptrace`?  On my system, `man 2 ptrace` gives a decent summary at the top:

> The **ptrace()** system call provides a means by which one process (the "tracer") may observe and control the execution of another process (the "tracee"), and examine and change the tracee's memory and registers. It is primarily used to implement breakpoint debugging and system call tracing.

"system call tracing" is what we're looking for- but I'm not sure a
`ptrace`-based tool is quite what we want.

I've used `ptrace` directly before, doing something like [Wine]:
running a program "not for Linux" under Linux, by intercepting all system calls.
The way `ptrace` works is:

1.  Tracer "attaches" to tracee
2.  Whenever the tracee makes a system call, or receives a signal, the kernel
    stops the tracee and switches to the tracer.
3.  Then the tracer can poke at the tracee's memory or registers. The tracer can
    replace or bypass the system call / signal on the tracee's behalf.
4.  Once the tracer is done with "whatever", it tells the kernel how to
    continue, which may allow the tracee to resume.

[Wine]: https://www.winehq.org/

This is **great for understanding**! Because it can read the process's memory,
it can work out all the arguments, like "this is the path that the `open`
call tried to open". Julia Evans has a
[nice roundup](https://jvns.ca/blog/2021/04/03/what-problems-do-people-solve-with-strace/)
of problems that `strace` can solve!

But this kind of tracing **changes the performance of the program**. We aren't
seeing how long it takes for the tracee to complete; we're also seeing how long
the tracer takes to say "go ahead".

What other options do we have?

### `perf`

I learned a lot about `perf` from [this zine](https://wizardzines.com/zines/perf/),
and there's more info at [Brendan Gregg's site](https://www.brendangregg.com/perf.html).

The Linux kernel has support for different kinds of performance
monitoring; `perf` is a nicely scriptable interface to this support.
One thing Linxu and `perf` can do is trace system calls!

When enabled, the kernel will log system calls into an in-memory buffer,
then `perf` can read them out. Unlike `strace`, the "tracer" sees the system
call after the fact- the kernel doesn't wait until the
event is seen by the tracer to service it. This means **`perf trace` has very
low performance cost** compared to `ptrace`- there's no waiting for another
user program.

(At least, in theory - I haven't measured the performance difference!)

The drawback is that `perf` doesn't capture caller-side details of the system
calls. Look at what `strace` and `perf` show for a shell running `echo hi`:

```shell
∵ strace sh -c 'echo hi >/dev/null' 2>&1 | grep write
write(1, "hi\n", 3)                     = 3
∵ sudo perf trace sh -c 'echo hi >/dev/null'  2>&1 | grep write
     0.294 ( 0.001 ms): sh/56499 write(fd: 1, buf: 0x55808bc98780, count: 3)                           = 3
```

`strace` shows us the string, while `perf` just shows the pointer.

It seems like `perf` will be better at performance, but worse for debugging.
That's OK! We'll still with looking for performance for now.

## Procedure

Let's talk about our test subjects- "hello world" across languages. For this
experiment, we're going to say "a hello world program" is:

-   A file
-   Executable by my Linux install
-   That prints the string `Hello, world!\n` to its standard output

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
    clear the page cache between runs.

Then it's just some processing of the `perf` output to get the numbers.

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

Here's results ([raw data](1-hello-bench/server.csv)) from a server (VM):

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

And results ([raw data](1-hello-bench/laptop.csv)) from a laptop:

mode     | sut      | mean   | median | min    | max
---------|----------|--------|--------|--------|-----
base     | 5-c      | 0.0002 | 0.0002 | 0.0002 | 0.0003
base     | 7-rust   | 0.0003 | 0.0003 | 0.0003 | 0.0004
base     | 1-dash   | 0.0003 | 0.0003 | 0.0002 | 0.0003
base     | 2-bash   | 0.0006 | 0.0006 | 0.0005 | 0.0008
base     | 6-cpp    | 0.0007 | 0.0006 | 0.0006 | 0.0008
base     | 8-golang | 0.0008 | 0.0009 | 0.0007 | 0.001
base     | 3-zsh    | 0.0008 | 0.0008 | 0.0007 | 0.001
base     | 4-python | 0.0088 | 0.0087 | 0.0083 | 0.0098
no_cache | 5-c      | 0.0002 | 0.0002 | 0.0002 | 0.0002
no_cache | 1-dash   | 0.0003 | 0.0003 | 0.0002 | 0.0003
no_cache | 7-rust   | 0.0006 | 0.0006 | 0.0005 | 0.0007
no_cache | 6-cpp    | 0.0006 | 0.0006 | 0.0006 | 0.0007
no_cache | 2-bash   | 0.0008 | 0.0008 | 0.0007 | 0.0008
no_cache | 8-golang | 0.0009 | 0.0009 | 0.0007 | 0.001
no_cache | 3-zsh    | 0.0014 | 0.0014 | 0.0012 | 0.0015
no_cache | 4-python | 0.0141 | 0.0141 | 0.0131 | 0.0152

[^prereqs]: The prerequisites are: `clang` and `clang++` for C and C++; `cargo` for Rust; `python3` for Python; `zsh`, `bash`, and `dash` for the shells.

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
a future post <!-- TODO -->, but I was surprised by how long it took on the
server in particular. Related to core count, maybe?

**All of these are very fast!** 60fps video is $ 1000 / 60 = 16.66... $
milliseconds per frame; Python is the only one of these that would have trouble
_starting a new process every frame_ and keeping up... at least, as far as
the program itself goes.

## Let me know what you think!

I'm planning on posting [more in this series](0-outline.md), so check back!

If you have answers, more questions, or suggestions, [reach out](https://cceckman.com)!

