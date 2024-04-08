---
title: "Startup Showdown 1 - Hello"
author: "Charles Eckman <charles@cceckman.com>"
date: 2024-04-08
---

To kick off the [startup showdown](..), let's write "hello world"
in several languages, and see what program(s) get to their output first.

## What comes before "Hello"? {#intro}

The [classic][jargon] "hello world"
program is the first you'll see in a lot of languages. As it turns out, it's
also a really nice way to measure how long a program takes to get to "our code"!

[jargon]: http://www.catb.org/jargon/html/H/hello-world.html

I'll write more about how program startup works in a later post.
For now, I'll say it's something like:
<!-- TODO: Link to chapter 4 -->

1.  Some program makes an [`exec`][exec] call, "please start this other program".
2.  The kernel loads the new program. When the kernel is done with this step,
    the kernel switches control to the new program.
3.  The _runtime_ for the new program's language starts, and prepares to run
    the code we wrote.
4.  Our code runs: a [`write`][write] call, "Hello, world!"

[exec]: https://man7.org/linux/man-pages/man3/exec.3.html
[write]: https://man7.org/linux/man-pages/man2/write.2.html

The "cost" I want to measure is the combination of (2) and (3). Depending
on language, and on other choices we make in preparing the program,
those steps might be more or less costly.

The neat thing about "hello, world" is that **step 3 is really easy to see**.[^exec-enter]
Since (2) and (4) are both system calls, we can use one of several mechanisms 
to see the 2-to-3 and 3-to-4 transitions. 
Subtract them, and we have "the language runtime's startup cost". Done!

[^exec-enter]: It would be better still to time the entry to (2), i.e. when the system call enters. I think this is possible, but it requires more careful handling of the `perf` invocation and output. I'm working on that, and will update this series with more results.

## Peeking at system calls

How do we see what system calls a procses makes, and when?

For some things we might use a debugger like `gdb` or `lldb`,
but I'm familiar with them as interactive tools more than batch operations.
For "collect then analyze" flows, I'm more familiar with `strace`--
and, after writing this article, `perf`.

I'm still learning about all of these tools (there's a lot to learn!)
I think for this case, I want to use **`perf` for timing information**.
I'll use `strace` later to better understand what each runtime is doing.

<!-- TODO : Extract this to a tangent, and run the numbers on timing -->

### `strace` and `ptrace`

`strace` runs a program, the "tracee", and records all of the program's system calls along with their arguments.

Here's the first few lines of `strace` tracing `true`:

```shell
∵ strace true 2>&1 | head -5
execve("/usr/bin/true", ["true"], 0x7ffefe7c67c0 /* 45 vars */) = 0
brk(NULL)                               = 0x55d3a6dd6000
mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6344a44000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
```

For more fun, here's a snippet of `strace` tracing `strace` tracing `true`:

```shell
∵ strace strace -o /dev/null true 2>&1 | head -100 | tail -5
wait4(60084, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTRAP | 0x80}], 0, NULL) = 60084
ptrace(PTRACE_GET_SYSCALL_INFO, 60084, 88, {op=PTRACE_SYSCALL_INFO_ENTRY, arch=AUDIT_ARCH_X86_64, instruction_pointer=0x7f8107a4e719, stack_pointer=0x7fffacc41b48, entry={nr=__NR_chdir, args=[0x5577a886bc81, 0xbad1fed1, 0xbad2fed2, 0xbad3fed3, 0xbad4fed4, 0xbad5fed5]}}) = 80
ptrace(PTRACE_SYSCALL, 60084, NULL, 0)  = 0
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_TRAPPED, si_pid=60084, si_uid=1000, si_status=SIGTRAP, si_utime=0, si_stime=0} ---
wait4(60084, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTRAP | 0x80}], 0, NULL) = 60084
```

We can see that `strace` uses `ptrace` system calls do its job.
Here's more of those `ptrace` calls:

```shell
∵ strace strace -o /dev/null true 2>&1 | grep ptrace | head -5
openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libunwind-ptrace.so.0", O_RDONLY|O_CLOEXEC) = 3
ptrace(PTRACE_SEIZE, 55678, NULL, 0)    = 0
ptrace(PTRACE_SETOPTIONS, 55679, NULL, PTRACE_O_TRACESYSGOOD) = 0
ptrace(PTRACE_GET_SYSCALL_INFO, 55679, 88, {op=PTRACE_SYSCALL_INFO_NONE, arch=AUDIT_ARCH_X86_64, instruction_pointer=0x7f035c4be267, stack_pointer=0x7ffcd5d9c3f8}) = 24
ptrace(PTRACE_SYSCALL, 55679, NULL, 0)  = 0
```

What's `ptrace`? To the [manual pages](https://man7.org/linux/man-pages/man2/ptrace.2.html)!

> The **ptrace()** system call provides a means by which one process (the "tracer") may observe and control the execution of another process (the "tracee"), and examine and change the tracee's memory and registers. It is primarily used to implement breakpoint debugging and system call tracing.

"system call tracing" is what we're looking for, for this exercise-
but still, `ptrace` may not be the right tool for the job.

A `ptrace` flow looks like this:

1.  The tracer calls `ptrace` to "attach" to the tracee.
2.  Whenever the tracee makes a system call, or receives a signal, the kernel
    _stops_ the tracee and wakes the _tracer_.
3.  The tracer can poke at the tracee's memory or registers. The tracer can
    modify the system call / signal, both inbound (to the process) and outbound (to the kernel).
4.  Once the tracer is ready, the tracer tells the kernel how to
    continue. This can cause the tracee to resume.

This is **great for debugging**! Because the tracer can read the tracee's memory,
the tracer can see all the system call arguments, like "this is the path that the `open`
call tried to open". Julia Evans has a
[nice roundup](https://jvns.ca/blog/2021/04/03/what-problems-do-people-solve-with-strace/)
of problems that `strace` can solve-- most of which are debugging / reverse engineering.

But I think this kind of tracing **changes the performance**.
Even if the tracer just passes everything through, we're timing the tracee _and_ the tracer.
That's not what we want: we want our timing to be minimally invasive.

Luckly, we have another option for that:

### `perf`

I learned a lot about `perf` from [this zine](https://wizardzines.com/zines/perf/),
and there's more info at [Brendan Gregg's site](https://www.brendangregg.com/perf.html).

The Linux kernel can do several kinds of performance monitoring / profiling / tracing.
One of those mechanisms is to trace system calls: when enabled, each matching system call
is logged into an in-memory buffer. The buffer is eventually handed off to a
userspace process... like `perf`!

This separation means that the `perf` tool isn't in the hot path of system calls;
it's only observing them after-the-fact.[^amortization] In theory, this means
the times reported by `perf` should be truer to the underlying program; though
in practice, I haven't done this measurement.[^meta]

[^amortization]: This might not be entirely true: I'm not sure what happens if
    the system is generating events faster than `perf` can process the buffers.
    In these tests, I'm only generating a couple of events in invocation, so
    it's not an immediate problem.
[^meta]: "Performance analysis of performance analysis techniques". If you do this, let me know!

The drawback is that `perf` doesn't capture caller-side details of the system
calls. Look at what `strace` and `perf` each show for a shell running `echo hi`:

```shell
∵ strace sh -c 'echo hi >/dev/null' 2>&1 | grep write
write(1, "hi\n", 3)                     = 3
∵ sudo perf trace sh -c 'echo hi >/dev/null'  2>&1 | grep write
     0.294 ( 0.001 ms): sh/56499 write(fd: 1, buf: 0x55808bc98780, count: 3)  = 3
```

`strace` shows us the string, while `perf` just shows the string's address.

That's fine for these tests, where we're just looking at performance!

## Experimental procedure

Let's talk about our test subjects-- "hello world" across languages. For this
experiment, "a hello world program" is:

- A file, that is
- Executable by my (Debian) Linux install,
- That prints the string `Hello, world!\n` to its standard output.

This uniformity comes from my [original question](../#original)-- we're going to
invoke every one as `./test`, regardless of language.

To time the program, we'll run it under `perf record`. We can look at the
time of [steps (3)](#intro) by filtering down to the right system
calls, and write to a file for later analysis:

```shell
perf record \
    --output="/tmp/perf.out" \
    --event="syscalls:sys_exit_execve,syscalls:sys_enter_write" \
    ./my-test-binary
```

### Checking the page cache

One thing I expect will have some impact on performance is the [page cache].
A frequently-used binary will probably be cached in-memory, so it will be faster
to start: it won't need to be pulled from storage.

[page cache]: https://www.kernel.org/doc/html/v6.3/admin-guide/mm/concepts.html#page-cache

I want to see how different languages interact with page cache; so,
we'll do two sets of runs for each program.

- One run will "just" run the program repeatedly, simulating a frequently-used program.

- One run will clear the page cache between runs, simulating a rarely-used program.

Then we'll do some processing of the `perf` output to get the numbers.

### Subjects

I've written up 8 "hello" programs:

1.  A shell script, specifying different shells:
    1.  `#!/usr/bin/dash`, the [Debian Alquist Shell](https://wiki.archlinux.org/title/Dash), designed to be a minimal POSIX-compliant shell
    2.  `#!/usr/bin/bash`, the Bourne Again Shell, a common default shell
    3.  `#!/usr/bin/zsh`, the Z Shell, the shell I use
2.  Python
3.  Javascript (using Node.js's [single executable application](node-app) feature)
4.  C-like: compiled to machine code
    1.  C
    2.  C++
    3.  Rust
5.  Golang

[node-app]: https://nodejs.org/api/single-executable-applications.html

All programs are built an run in "as default a manner" as possible:
no optimization flags, link flags or anything else.

## The results

These are my results, but **you can run this yourself!!**

The code is in [repository](https://github.com/cceckman/startup-showdown),
including the orchestrator. If you have the compilers/interpreters installed[^prereqs],
you can download and run `./do` and see how the results for your machine.

On a server-class machine, in a VM with 10 threads:

mode     | sut    | mean   | median | min    | max
---------|--------|-------:|-------:|-------:| ---:
base     | c      | 0.0005 | 0.0005 | 0.0005 | 0.0005
base     | dash   | 0.0006 | 0.0006 | 0.0006 | 0.0007
base     | rust   | 0.0008 | 0.0008 | 0.0007 | 0.0011
base     | cpp    | 0.0014 | 0.0014 | 0.0014 | 0.0015
base     | bash   | 0.0015 | 0.0014 | 0.0013 | 0.0026
base     | zsh    | 0.0018 | 0.0018 | 0.0018 | 0.0019
base     | golang | 0.0029 | 0.0027 | 0.0019 | 0.0054
base     | python | 0.0154 | 0.0151 | 0.0143 | 0.0182
base     | node   | 0.0423 | 0.0358 | 0.0328 | 0.0980
no_cache | c      | 0.0005 | 0.0005 | 0.0005 | 0.0005
no_cache | dash   | 0.0006 | 0.0006 | 0.0006 | 0.0006
no_cache | rust   | 0.0011 | 0.0011 | 0.0011 | 0.0013
no_cache | cpp    | 0.0015 | 0.0015 | 0.0014 | 0.0016
no_cache | zsh    | 0.0024 | 0.0024 | 0.0023 | 0.0033
no_cache | bash   | 0.0033 | 0.0033 | 0.0030 | 0.0042
no_cache | golang | 0.0047 | 0.0043 | 0.0038 | 0.0056
no_cache | python | 0.0186 | 0.0183 | 0.0178 | 0.0213
no_cache | node   | 0.0856 | 0.0834 | 0.0809 | 0.1044

[^prereqs]: The prerequisites are: `clang` and `clang++` for C and C++; `cargo` for Rust; `python3` for Python; `zsh`, `bash`, and `dash` for the shells; `node` and `npx` for Javascript (>v19; I used v20).

### What's wrong with this picture?

I know there's some issues with this test setup that impact the results,
so let me call them out before going further.

#### `no_cache` doesn't mean anything for `dash` {#dash}

I'm making `no_cache` happen by writing to `/proc/sys/vm/drop_caches`
(documentation provided by [the Linux kernel](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)).

This has some effect...but not a lot. At least for `dash`, we can explain why.

The test runner I'm using is `./do`, the
[minimal version](https://github.com/apenwarr/redo/tree/main/minimal)
of Avery Pennarun's [redo](https://github.com/apenwarr/redo). This uses the
system shell:

```
$ head -1 ./do
#!/usr/bin/env sh
```

Which is `dash` on my system.

I'm pretty sure the `dash` program itself will still be in memory when we
get to that test; we dump the page cache, then hop back to shell execution
to run run the test program. This means our _test fixture_ pays the
"load the interpreter" penalty, but the _system under test_ doesn't.

(Still - almost as fast as C? Nice job, `dash` authors!)

#### `no_cache` matters less for `libc` programs {#libc}

Similarly, I think all of these (except Go) wind up using the same shared
library - the system `libc`. I expect that's a decent fraction of the code
for several of these, which again will be paid in part by the test fixture
instead of the test.

### Observations

**C is fast.** Not surprising, but it's good to see how fast. [For future
investigation](..) - how much of that is because [`libc` is already in
memory?](#libc)

**`dash` is almost as fast as C.** Even given the [above](#dash) observation on
residency, I'm still impressed that it can parse & complete the script before
most compiled programs.

**Go is takes longer than I expected.** I'll want to analyze Go startup more in
a future post, but I was surprised by how long it took on the
server in particular. Related to core count, maybe?

**All of these are very fast.** 60fps video is \\( 1000 / 60 = 16.66... \\)
milliseconds per frame. Python is the only one of these that would have trouble
_starting a new process every frame_ and keeping up... if it's not really
doing anything during execution.

## Let me know what you think!

I'm planning on posting [more in this series](..), so check back!

If you have answers, more questions, or suggestions, [reach out](https://cceckman.com)!

## Acknowledgements

Thanks to Meg, Claire, Nic, and Aditya for reviewing this.

Much of the work for this series was done at [the Recurse Center](https://www.recurse.com/scout/click?t=8238c6d9149cbd0865752e535795d509).
