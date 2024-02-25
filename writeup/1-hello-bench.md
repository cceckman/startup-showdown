# Startup Showdown: Hello

author: "Charles Eckman <charles@cceckman.com>"
date: 2024-02-25
---

What's the baseline startup cost for programs in different languages?
To kick off the [startup showdown](0-outline.md), let's write "hello world"
in different ways, and see what program(s) get to their output first.

---

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

What should we use?

I'll go over my thinking here, but quick unsolicited plug: Julia Evans' [blog][jvns] and [Wizard Zines][wizard-zines] have helped me understand what these tools do and
how to use them!

[jvns]: https://jvns.ca/
[wizard-zines]: https://wizardzines.com


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

On my system, `man 2 ptrace` says:

> The **ptrace()** system call provides a means by which one process (the "tracer") may observe and control the execution of another process (the "tracee"), and examine and change the tracee's memory and registers. It is primarily used to implement breakpoint debugging and system call tracing.

That _sounds_ like what we want! But...maybe not.

I've used `ptrace` before- a fun little project replacing the Linux system call
ABI with a non-Linux one. The way `ptrace` works is:

1.  Tracer "attaches" to tracee
2.  When tracee makes a system call or receives a [signal], the kernel stops
    the tracee, and unblocks the tracer.
3.  The tracer can poke at the tracee's memory or registers, and replace or
    bypass the system call / signal on the tracee's behalf.

[signal]: <!-- TOOD -->

This is **great for understanding**! `strace` tells us things like the values
of strings - what we want and need to understand what the system call is doing.
Again, I'll point to [Julia Evans](https://jvns.ca/blog/2021/04/03/what-problems-do-people-solve-with-strace/) for "what problems can `strace` help with".

But this **changes the performance of the program**. We aren't seeing how long
it takes for the tracee to complete - we're also seeing how long the tracer
takes.

What other options do we have?

### `perf`

I learned a lot about `perf` from [this zine](https://wizardzines.com/zines/perf/)!

The Linux kernel has a whole system for different kinds of performance
monitoring- [profiling, tracing, and counting][kinds]. When enabled, the kernel
will log when certain events occur into a ring buffer. **This is fast**, so it
won't do much to change the performance characteristics of the binary under
test.

The drawback is that `perf` doesn't capture process-level details:

```shell
∵ strace sh -c 'echo hi >/dev/null' 2>&1 | grep write
write(1, "hi\n", 3)                     = 3
∵ sudo perf trace sh -c 'echo hi >/dev/null'  2>&1 | grep write
     0.294 ( 0.001 ms): sh/56499 write(fd: 1, buf: 0x55808bc98780, count: 3)                           = 3
```

So (in my opinion) it's less good for **understanding what a program is doing**.


[kinds]: <!-- TODO - say more about different kinds of collection. jvns' zine calls out that _events_ mean _profiling_ is not done, which I learned today -->

### perf for times, strace for meaning?

Both of these tools can be useful!

-   We can use `perf` to generate timings
-   We can use `strace` to work out what happened

For now, we'll stick with `perf`- just getting the baseline measurements.

<!-- TODO: add link -->

## The programs



## The results



