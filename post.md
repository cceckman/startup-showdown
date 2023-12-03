# Startup Showdown

cceckman  
2023-11-21 and later

## Introduction

I use a lot of command-line tools. Other people's tools like `git`, `hg`, `rg`; my own [scripts](https://github.com/cceckman/Tilde/tree/main/scripts) to make certain tasks easier.

Command-line tools can differ from other programs in that they are *especially* transient: they run for a short amount of time, possibly on very few inputs.

There's some conventional wisdom that starting up a process can be more expensive than whatever the process is doing. For instance, Wikipedia has a header for the ["useless use of `cat`"](https://en.wikipedia.org/wiki/Cat_(Unix)#Useless_use_of_cat) lint.[^wiki]

[^wiki]: Mostly, this tells us about Wikipedia's authoring and editing community...

I got curious:

- How long does it take to start a process? Why?
- How do those startup costs compare across languages?

This post describes a set of experiments to answer these questions.
## What I know going in

There's a bunch of up-front costs to starting a process. Some of these are because of the operating system (specifically, the kernel): setting up page tables, tracking structures, copying memory around...

Other costs are language-dependent:
- C, C++, and Rust (by default) perform dynamic linkage against a `libc` implementation, and possibly other libraries; the loading phase happens in userspace, and can take a chunk of time.
- Interpreted languages like Python and shell run under an interpreter, which is itself a C/C++ binary; then, interpreting the code, checking for syntax errors, etc. takes some time.
- Golang has a garbage-collecting, thread-managing runtime that require some setup. But Golang doesn't link to `libc`.

All of these are things that I can influence when writing a command-line tool- by choosing my language, linkage, etc. to make it fast.

Of course, this isn't the *only* factor in those choices- language familiarity, libraries, etc. also matter A Lot. But I'd like to *know* the tradeoff I'm making, rather than just assuming.
### _In Situ_ measurements
Before writing my own benchmarks, I want to validate that "different stuff is going on" using existing programs.

I've occasionally used the `strace` tool to look at this kind of thing, which records every system call. More recently I've used `perf` for a similar task ([Julia Evans](https://jvns.ca/blog/2015/03/30/seeing-system-calls-with-perf-instead-of-strace/) on the subject); it seems like `perf` might be using a more-performant mechanism for recording.

Let's see what they both have to say about a few programs. Note that I'm not (yet) trying to get reproducible results or timings- just a general idea about what's going on in each of these.

I'll start by making sure the tools, and programs, are installed:

```shell
∵ sudo apt-get install strace linux-perf mercurial ripgrep git
```

(Tailscale has some additional steps; see their site.)

TODO: Tailscale link above

<details>
<summary>`hg status` (Python) reads the local `.hg` directory after about half a second. The intermediate time is mostly spent loading Python modules, though it includes loading a couple C libraries as well.</summary>

I ran `hg` in my `git` directory:

```shell
∵ strace -ttt -o static/hg.strace.txt hg status
abort: no repository found in '/home/cceckman/r/github.com/cceckman/startup-showdown' (.hg not found)
∴ 255 startup-showdown:main…startup-showdown
∵ sudo perf trace -o static/hg.perf hg status
abort: no repository found in '/home/cceckman/r/github.com/cceckman/startup-showdown' (.hg not found)
∴ 0 startup-showdown:main…startup-showdown
```

Here's the [`strace`](static/hg.strace.txt) and [`perf`](static/hg.perf) files.

The `strace` output is a little more useful - it has the filenames resolved, instead of just pointers.

We start by pulling in the dynamic loader:

```
1700837164.739205 openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
```

And loading (reading, mapping) a number of libraries- selected lines:

```
1700837164.741083 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libz.so.1", O_RDONLY|O_CLOEXEC) = 3
...
1700837164.742425 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libexpat.so.1", O_RDONLY|O_CLOEXEC) = 3
...
1700837164.743794 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
```

There's some interesting calls once `libc` is loaded: `set_tid_address`, `rseq`, `getrandom`... and opening `locale-archive` and `gconv-modules.cache` files. It's not obvious to me which of these are `python` setup calls, and which of these are `libc`.

The first that's clearly `python` is:

```
1700837164.781304 newfstatat(AT_FDCWD, "/usr/bin/pyvenv.cfg", 0x7ffcaa4fc780, 0) = -1 ENOENT (No such file or directory)
```

about ~17 ms after the `execve` call.

There's a _lot_ of `newfsstatat` calls for things that look like Python system files - mostly which don't exist. Installing signal handlers with `rt_sigaction`, more looking for customizations... then finally we get to Mercurial proper:

```
1700837164.793901 newfstatat(AT_FDCWD, "/usr/bin/hg", {st_mode=S_IFREG|0755, st_size=1705, ...}, 0) = 0
1700837164.794048 openat(AT_FDCWD, "/usr/bin/hg", O_RDONLY|O_CLOEXEC) = 3
```

That's >100ms of Python startup, before we do anything for `hg` itself.

Mercurial (quite reasonably) loads a bunch of Python modules from various paths, e.g.:

```
1700837164.809683 newfstatat(AT_FDCWD, "/usr/bin", {st_mode=S_IFDIR|0755, st_size=36864, ...}, 0) = 0
1700837164.809860 newfstatat(AT_FDCWD, "/usr/lib/python3.11", {st_mode=S_IFDIR|0755, st_size=12288, ...}, 0) = 0
1700837164.810015 newfstatat(AT_FDCWD, "/usr/lib/python3.11/keyword.py", {st_mode=S_IFREG|0644, st_size=1061, ...}, 0) = 0
1700837164.810187 newfstatat(AT_FDCWD, "/usr/lib/python3.11/keyword.py", {st_mode=S_IFREG|0644, st_size=1061, ...}, 0) = 0
1700837164.810322 openat(AT_FDCWD, "/usr/lib/python3.11/__pycache__/keyword.cpython-311.pyc", O_RDONLY|O_CLOEXEC) = 3
1700837164.810441 newfstatat(3, "", {st_mode=S_IFREG|0644, st_size=1068, ...}, AT_EMPTY_PATH) = 0
1
```

I note that it stats the `<module>.py` file, then opens `__pycache__/<module>.cpython-311.pyc` - automatically picking up the cached bytecode.

Skipping ahead: what is Mercurial doing specific to this invocation? Searching
for my username might give a hint.

```
1700837165.134460 openat(AT_FDCWD, "/home/cceckman/.hgrc", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
1700837165.134598 openat(AT_FDCWD, "/home/cceckman/.config/hg/hgrc", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
```

is still more or less Mercurial startup. After that I see a bunch of loading
_Mercurial-specific_ modules:

```
1700837165.148398 newfstatat(AT_FDCWD, "/usr/lib/python3/dist-packages/mercurial/rewriteutil.py", {st_mode=S_IFREG|0644, st_size=8708, ...}, 0) = 0
```

Eventually we get down to the invocation we want:

```
1700837165.219930 getcwd("/home/cceckman/r/github.com/cceckman/startup-showdown", 1024) = 54
1700837165.220081 newfstatat(AT_FDCWD, "/home/cceckman/r/github.com/cceckman/startup-showdown/.hg", 0x7ffcaa4fd090, 0) = -1 ENOENT (No such file or directory)
1700837165.220242 newfstatat(AT_FDCWD, "/home/cceckman/r/github.com/cceckman/.hg", 0x7ffcaa4fd090, 0) = -1 ENOENT (No such file or directory)
1700837165.220391 newfstatat(AT_FDCWD, "/home/cceckman/r/github.com/.hg", 0x7ffcaa4fd090, 0) = -1 ENOENT (No such file or directory)
1700837165.220541 newfstatat(AT_FDCWD, "/home/cceckman/r/.hg", 0x7ffcaa4fd0e0, 0) = -1 ENOENT (No such file or directory)
1700837165.220704 newfstatat(AT_FDCWD, "/home/cceckman/.hg", 0x7ffcaa4fd0e0, 0) = -1 ENOENT (No such file or directory)
1700837165.220852 newfstatat(AT_FDCWD, "/home/.hg", 0x7ffcaa4fd0e0, 0) = -1 ENOENT (No such file or directory)
1700837165.220999 newfstatat(AT_FDCWD, "/.hg", 0x7ffcaa4fd0e0, 0) = -1 ENOENT (No such file or directory)
```

This is where the program is doing "what we asked", looking for the current Mercurial state.

Without having optimized or controlled for anything:

$$
1700837165.219930 - 1700837164.737866 = 0.482...
$$

not quite half a second of startup time.

Mercurial in particular has a helper program called `chg`, which acts as a daemon
to help avoid some of these costs. But... that is a whole 'nother program to maintain.

TODO: link to `chg`

</details>

<details>
<summary>`git status` (C) reads the `.git` directory after about 10ms.</summary>

```
∵ strace -ttt -o static/git.strace.txt git status
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   post.md

no changes added to commit (use "git add" and/or "git commit -a")
∴ 0 startup-showdown:main…startup-showdown
∵ sudo perf trace -o static/git.perf git status
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   post.md

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        .redo/
        static/

no changes added to commit (use "git add" and/or "git commit -a")
∴ 0 startup-showdown:main…startup-showdown
```

Oops - guess I need to stage some stuff.

We start off, as always, with the `execve` call; and the typical-C `ld.so` dance:

```
1700837990.631952 execve("/usr/bin/git", ["git", "status"], 0x7ffe560697a0 /* 31 vars */) = 0
1700837990.632596 brk(NULL)             = 0x55d7ed978000
1700837990.632790 mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7facbabb9000
1700837990.632950 access("/etc/ld.so.preload", R_OK) = -1 ENOENT (No such file or directory)
1700837990.633221 openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
```

Like `python3`, `git` loads `libz` befor `libc`:

```
1700837990.634708 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libz.so.1", O_RDONLY|O_CLOEXEC) = 3
...
1700837990.635711 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
```

And a lot of the following calls look common with the `hg` trace, up to:

```
1700837990.638502 prlimit64(0, RLIMIT_STACK, NULL, {rlim_cur=8192*1024, rlim_max=RLIM64_INFINITY}) = 0
1700837990.638675 munmap(0x7facbabb1000, 31538) = 0
```

After that, the traces start diverging; this might tell us where the static-init
phase of the binary starts (the stuff that happens before `main`).

We get to application-specific I/O pretty quickly- without, apparently, loading e.g. `libgit` or similar:

```
1700837990.640672 access("/etc/gitconfig", R_OK) = -1 ENOENT (No such file or directory)
1700837990.640839 access("/home/cceckman/.config/git/config", R_OK) = -1 ENOENT (No such file or directory)
1700837990.640966 access("/home/cceckman/.gitconfig", R_OK) = 0
1700837990.641092 openat(AT_FDCWD, "/home/cceckman/.gitconfig", O_RDONLY) = 3
```

And after reading that, work on the actual question we've asked:

```
1700837990.641797 getcwd("/home/cceckman/r/github.com/cceckman/startup-showdown", 129) = 54
1700837990.641917 getcwd("/home/cceckman/r/github.com/cceckman/startup-showdown", 129) = 54
1700837990.642024 newfstatat(AT_FDCWD, "/home/cceckman/r/github.com/cceckman/startup-showdown", {st_mode=S_IFDIR|0755, st_size=4096, ...}, 0) = 0
1700837990.642143 newfstatat(AT_FDCWD, "/home/cceckman/r/github.com/cceckman/startup-showdown/.git", {st_mode=S_IFDIR|0755, st_size=4096, ...}, 0) = 0
```

Without any optimizations,

$$
1700837990.641797 - 1700837990.631952 = 0.0098...
$$

about 10 ms of startup.

</details>


<details>
<summary>`rg` (Rust) loads more libraries than Git to begin with, but starts processing input after 22ms.</summary>

```shell
∵ echo hello | strace -ttt -o static/rg.strace.txt rg 'hello' -
hello
∴ 0 startup-showdown:main…startup-showdown
∵ echo hello | sudo perf trace -o static/rg.perf rg 'hello' -
hello
∴ 0 startup-showdown:main…startup-showdown
```

Again, we're expecting to see `lib` in here, for a default Rust build. And we do, along with a number of other library loads:

```
1700838950.226057 execve("/usr/bin/rg", ["rg", "hello", "-"], 0x7fffef88f8b8 /* 31 vars */) = 0
...
1700838950.227165 access("/etc/ld.so.preload", R_OK) = -1 ENOENT (No such file or directory)
1700838950.227484 openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.228097 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libpcre2-8.so.0", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.229301 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libgcc_s.so.1", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.230483 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libm.so.6", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.231729 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
```

And again the `libc` startup sequence - reproduced here in (maybe?) its entirety:

```
1700838950.233244 close(3)              = 0
1700838950.233400 mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f9d57746000
1700838950.233560 arch_prctl(ARCH_SET_FS, 0x7f9d57747100) = 0
1700838950.233683 set_tid_address(0x7f9d577473d0) = 368718
1700838950.233804 set_robust_list(0x7f9d577473e0, 24) = 0
1700838950.233909 rseq(0x7f9d57747a20, 0x20, 0, 0x53053053) = 0
1700838950.234103 mprotect(0x7f9d57916000, 16384, PROT_READ) = 0
1700838950.234300 mprotect(0x7f9d57a06000, 4096, PROT_READ) = 0
1700838950.234472 mprotect(0x7f9d57a26000, 4096, PROT_READ) = 0
1700838950.234620 mprotect(0x7f9d57ac0000, 4096, PROT_READ) = 0
1700838950.235167 mprotect(0x561ce7703000, 229376, PROT_READ) = 0
1700838950.235343 mprotect(0x7f9d57afc000, 8192, PROT_READ) = 0
1700838950.235523 prlimit64(0, RLIMIT_STACK, NULL, {rlim_cur=8192*1024, rlim_max=RLIM64_INFINITY}) = 0
1700838950.235720 munmap(0x7f9d57ac2000, 31538) = 0
```

There's a bunch of very interesting calls immediately after this.

```
1700838950.236024 poll([{fd=0, events=0}, {fd=1, events=0}, {fd=2, events=0}], 3, 0) = 1 ([{fd=0, revents=POLLHUP}])
```

is followed by various signal-handler setup; and a fair amount of introspection
as to the runtime environment:

```
1700838950.237766 openat(AT_FDCWD, "/proc/self/maps", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.239070 close(3)              = 0
1700838950.239210 sched_getaffinity(368718, 32, [0 1 2 3 4 5 6 7]) = 8
...
1700838950.240576 openat(AT_FDCWD, "/proc/self/cgroup", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.241174 openat(AT_FDCWD, "/proc/self/mountinfo", O_RDONLY|O_CLOEXEC) = 3
...
1700838950.241738 openat(AT_FDCWD, "/sys/fs/cgroup/user.slice/user-1000.slice/session-1317.scope/cpu.max", O_RDONLY|O_CLOEXEC) = 3
```

My guess is that ripgrep is asking for "get number of valid CPUs", to start up
an appropriate number of worker threads for some purpose. That doesn't explain
to me the `mountinfo` or memory `maps`...

Shortly after this, we're definitely definitely in ripgrep's territory, checking
`.gitconfig` -> `.gitignore` to know which files to avoid checking:

```
1700838950.246563 openat(AT_FDCWD, "/home/cceckman/.gitconfig", O_RDONLY|O_CLOEXEC) = 3
...

1700838950.247650 statx(AT_FDCWD, "/home/cceckman/.gitignore_global", AT_STATX_SYNC_AS_STAT, STATX_ALL, {stx_mask=STATX_ALL|STATX_MNT_ID, stx_attributes=0, stx_mode=S_IFREG|0644, stx_size=49, ...}) = 0
```

Of course, we've asked `rg` to just check `stdin`, so this isn't really necessary.

But we can see it does do that job shortly:

```
1700838950.248298 close(3)              = 0
1700838950.248478 brk(0x561ce8f46000)   = 0x561ce8f46000
1700838950.248705 read(0, "hello\n", 8192) = 6

```

$$
1700838950.248705 - 1700838950.226057 = 0.0226..
$$

About 22ms to load libraries, config files, and start processing input.

</details>

<details>
<summary>`tailscale` (Golang)</summary>

Now for the weird one - with no `libc`.

TODO: I got this wrong the first time: need to invoke `strace` / `perf` to trace children as well, since Golang spins up many new threads _by default_. And need to carry that forward into the trace configuration for the microbenchmark. For strace that's `-f`

```
∵ strace -ttt -o static/tailscale.strace.txt tailscale status
[ output elided ]

# Health check:
#     - Linux DNS config not ideal. /etc/resolv.conf overwritten. See https://tailscale.com/s/dns-fight
∴ 0 startup-showdown:main…startup-showdown
∵ sudo perf trace -o static/tailscale.perf tailscale status
[ outut elided ]

# Health check:
#     - Linux DNS config not ideal. /etc/resolv.conf overwritten. See https://tailscale.com/s/dns-fight
∴ 0 startup-showdown:main…startup-showdown

```

We time from `execve`:

```
1700839854.000781 execve("/usr/bin/tailscale", ["tailscale", "status"], 0x7ffe222b70c0 /* 31 vars */) = 0
```

But our first calls after that are very different:

```
1700839854.001429 arch_prctl(ARCH_SET_FS, 0xf00210) = 0
1700839854.001699 sched_getaffinity(0, 8192, [0 1 2 3 4 5 6 7]) = 8
1700839854.001959 openat(AT_FDCWD, "/sys/kernel/mm/transparent_hugepage/hpage_pmd_size", O_RDONLY) = 3
1700839854.002240 read(3, "2097152\n", 20) = 8
1700839854.002435 close(3)              = 0
```

There's a similar `arch_prctl` call in the `libc` programs, but it occurs after loading `libc`.

The following calls are a bunch of `mmap` and `madvise` calls- not files, just private memory- and then signal-handler attachments...for _all_ signals?

```

1700839854.009727 rt_sigaction(SIGHUP, NULL, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=0}, 8) = 0
...
1700839854.022590 rt_sigaction(SIGRT_32, {sa_handler=0x46a940, sa_mask=~[], sa_flags=SA_RESTORER|SA_ONSTACK|SA_RESTART|SA_SIGINFO, sa_restorer=0x46aa80}, NULL, 8) = 0
```

Then we have 

```
1700839854.022737 rt_sigprocmask(SIG_SETMASK, ~[], [], 8) = 0
1700839854.022886 clone(child_stack=0xc000070000, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS, tls=0xc00005e090) = 368970
1700839854.023040 rt_sigprocmask(SIG_SETMASK, [], NULL, 8) = 0
1700839854.023151 --- SIGURG {si_signo=SIGURG, si_code=SI_TKILL, si_pid=368969, si_uid=1000} ---
```

which means I did the wrong thing in my `strace` invocation.

That `clone` call is, I think, saying that Golang is _immediately_ spawning off
another thread; before any I/O. This might be "application", in that it might be
when the Tailscale CLI first asks for a new goroutine... but from what I know of
the Golang runtime, I think it spins off the OS threads = number of CPUs
immediately on startup.

My guess is this routine is showing us:

- `sched_getaffinity` to get the number of CPUs
- `mmap` to set up stacks and data for each of the new threads
- launch of a new thread... but I didn't ask `strace` to trace children, so any calls from that thread are lost. Hrm.

I might need to rerun this. But continuing the read here:

There's a bunch of `SIGURG` handles, then another thread launch:

```
1700839854.027387 --- SIGURG {si_signo=SIGURG, si_code=SI_TKILL, si_pid=368969, si_uid=1000} ---
1700839854.027446 rt_sigreturn({mask=[]}) = 0
1700839854.027556 --- SIGURG {si_signo=SIGURG, si_code=SI_TKILL, si_pid=368969, si_uid=1000} ---
1700839854.027616 rt_sigreturn({mask=[]}) = 0
1700839854.027745 rt_sigprocmask(SIG_SETMASK, ~[], [], 8) = 0
1700839854.027930 clone(child_stack=0xc00006c000, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS, tls=0xc00005e490) = 368971
```

There's a couple more places of bouncing between `futex` and `clone`. Then
a set of calls that look like they're looking at the current system:

```
1700839854.031952 openat(AT_FDCWD, "/proc/sys/kernel/syno_hw_version", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
1700839854.032212 openat(AT_FDCWD, "/sys/firmware/devicetree/base/model", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
1700839854.032553 newfstatat(AT_FDCWD, "/usr/syno", 0xc0001acd38, 0) = -1 ENOENT (No such file or directory)
1700839854.032681 newfstatat(AT_FDCWD, "/usr/local/bin/freenas-debug", 0xc0001ace08, 0) = -1 ENOENT (No such file or directory)
1700839854.032793 newfstatat(AT_FDCWD, "/etc/debian_version", {st_mode=S_IFREG|0644, st_size=5, ...}, 0) = 0
1700839854.033162 readlinkat(AT_FDCWD, "/proc/self/exe", "/usr/bin/tailscale", 128) = 18
1700839854.033318 newfstatat(AT_FDCWD, "/var/run", {st_mode=S_IFDIR|0755, st_size=740, ...}, 0) = 0
```

This looks like user code - `tailscale` trying to figure out the platform it's running on. We're *definitely* executing Tailscale's code when the CLI connects to the daemon:

```
1700839854.033712 futex(0xc000090148, FUTEX_WAKE_PRIVATE, 1) = 1
1700839854.033944 socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
1700839854.034105 connect(3, {sa_family=AF_UNIX, sun_path="/var/run/tailscale/tailscaled.sock"}, 37) = 0
```

</details>

We'll look for the first thing that looks like "program work", and the time & count of system calls that happen before that.

### Considering tradeoffs
This post is trying to poke at the Pareto frontier: how fast *can* a launch be? With what amount of trouble?

TODO:
- Launch time isn't the only thing that matters, or even the most important thing that matters. Build time matters a lot when I'm iterating on something. Ease of writing matters a lot. Safety matters a lot.
	- Isolate this dimension from others for measurement; consider them together when evaluating tradeoffs.
- Benchmark below isn't representative, or complete.
	- `fork`-then-`exec` means our test runner affects the measured values!
- I'm looking exclusively at Linux.
	- Different OSes may have different characteristics and tradeoffs.
	- "Use a POSIX compatibility layer", "Use your language's standard library" are all great things to do! I wouldn't actually want to use [raw assembly].


## Microbenchmark

TODO: Want apples-to-apples comparisons. This won't be super realistic- I've [a "part 2" in mind]- but it should serve to get us some rough data, and set up a flow for something better.

Example program is just "hello world". In a syscall trace, we can tell when we're in user code when we write the output channel; in the end-to-end code, we're using `times(2)`.

Input: each case is:
- Build command-line
- Clean command-line
- Execute command-line

Procedure: for each case,

1. Switch to a dedicated user, clear out a lot of the environment. Try to avoid measuring my `.profile` or `PATH` costs!
2. Set CPU state:
	1. CPU mask (?)
	2. CPU power state
3. Create a buffer to use as `stdout`; write "hello world" to it, then rewind it
	1. We're reusing the same descriptor, and it's already used by the OS, so everyone gets the same thing
4. For each case,
	1. Compile
	2. Do an initial run:
		1. Clean up:
			1. Run custom "clean" command, if present
			2. Flush OS page cache (get reliable "read from filesystem" performance)
		2. Run
			1. Rewind `stdout`
			2. Get `times(2)`
			3. `fork` and `exec` to the new process, passing `stdout`
			4. `wait` for completion
			5. Get `times(2)` again; report/record system 
		3. Do (2) 3-5 more times, to record data points with a used page cache
		4. Do (1+2) 3-5 more times, to record more data points with an empty page cache
	3. Repeat (1), but under the tracer (`strace` or `perf`)

Note that in this experiment, we're _not_ measuring build performance; in fact, we're penalizing `python` by getting rid of its bytecode cache. I really do care about the speed of the build-test-run cycle for tools- we're just not measuring it in _this_ experiment.

TODO: I'm not sure `times` is going to be a sufficient measurement.

>  Times for terminated children (and their descendants) are added in at the moment wait(2) or waitpid(2) returns their process ID.

which means we're also measuring the time it takes for the parent to observe
the child has terminated.

Do we want to time instead:

- Write to stdout? That's capturing startup, not shutdown, which is what we are looking for.
	- Set up a zero-sized [`pipe`](https://man7.org/linux/man-pages/man2/pipe.2.html)?
- Or maybe what we really want to do is parse the `strace` or `perf` results. Without too much difficulty, we should be able to pick out `execve` and `write(1)`...


### Test categories

Below, I've split the programs into two batches.

[Batch 1] are unoptimized "hello world" programs in:
- POSIX Shell
- Python
- C
- C++
- Rust
- Golang

These all represent the "minimum effort" in that language, without any special optimizations; the performance I'd get if I just wrote the program, then stopped thinking about it.

[Batch 2] take the same programs (more or less), and modify the build in various ways to try to improve performance:

- Compiler optimizations
- Trimming dependencies
- Alternative `libc`
- Static linking
- Skipping `libc`
- Bytecode caching 

I've left for [later](<#Future work>) any efforts to optimize the program itself- we'd need a program more sophisticated than "hello world" to do that!
### Hypotheses
I've previously done tests _similar to_ this, when looking at embedded programs or when debugging. So my guesses going in:

- Dynamic linking will have the greatest effect. To a first approximation, the programs with the most (dynamic) libraries will take the longest to start up.
	- Among my tests, that means (Python, shell, C++, Rust), then (C), then (Golang).
- After that, interpretation will have the next-greatest effect, because it involves I/O - reading the input file, then dealing with that it means.
	- Specifically, CPython will be slowest because it will have to compile, then run; shell will be next-slowest; then the others as mentioned above.
- After that, runtime will have the next-greatest effect.
	- In my tests, I'd expect statically-linked C/C++/Rust to outperform Golang.

Let's see how wrong I am!

## Batch 1: Baseline programs

The first batch of tests give a program that prints "Hello, world!\n" and exits with code 0. We aren't doing anything fancy, special, optimized; we're just printing the message as simply as we can.

### Scripts: Shell and Python

Shell is the first thing I'm likely to reach for, when writing a tool for myself. Highly portable, no installation required; if what I'm doing is mostly orchestrating other processes, it's okay.

```shell
#!/bin/sh
echo "Hello, world!"
```

TODO: What is `sh` on my system? Let's try a few:

```shell
#!/bin/bash
echo "Hello, world!"
```

```shell
#!/bin/dash
echo "Hello, world!"
```

```shell
#!/bin/zsh
echo "Hello, world!"
```

But hard to do serious data manipulation, significant branches; and hard to maintain once it gets above a certain size.

Especially if I'm working with someone else, I'm likely to step up to Python:

```python
#!/usr/bin/python3
print("Hello, world!\n")
```
### Tradition: C and C++
Two compiled languages, well-established toolchains. Baseline of OSes; lots of stuff backs up to `libc`.

```c
#include <stdio.h>

int main() {
  (void)printf("Hello, world!");
  return 0;
}
```

```c++
#include <iostream>

int main() {
  std::cout << "Hello, world!" << std::endl;
  return 0;
}
```
### Modern: Rust
Rust specifically meant as a C/C++ successor. To that end, links `libc` (in most configurations; more [below]), though it handles things like formatting differently.

```rust
fn main() {
  println!("Hello, world!");
}
```

### Modern: Golang
TODO
Golang is a bit of a strange beast. Developed at Google, with Google's execution environment and microservice architecture in mind- and with developer velocity (build speed) as a very high priority.

Key differences from C/C++/Rust:
- No libc, statically linked
	- Static linkage - no dynamic linking to the other 
	- No "trampoline" to the `libc` routine
- Runtime
	- Garbage collection: we probably won't hit it in such a small program, but runtime still may set it up. That has a cost.
	- Host threads (TODO: What's Golang's name for this): Golang's "goroutines" (green threads) multiplex onto a different set of CPU threads; the main worker threads are one-per-CPU. The runtime may set these up even if we don't use them. That has a cost.
	- I/O offload: Golang moves goroutines to I/O threads (or converts a thread to an I/O thread?) before performing I/O; kind of like how other languages / runtimes handle [asynchrony]. This has a cost too.

```go
import "fmt"

func main() {
  fmt.Println("Hello, world!")
}
```

## Batch 1: Results

TODO

### By the numbers

### Trace analysis

## Batch 2: Optimized building

Some things we can do to change the launch behavior of the program, without really changing its text.

### Reference: Assembly
Wait, what?

No, I'm not going to write any tools in straight-up assembly. But it's a useful floor: what's the _best_ a language could _possibly_ do, if we took away safety guarantees, multithreading, readability... all those nice things. If we're looking to find the Pareto frontier, this is *probably* far off on one edge.

TODO: Find an "x86 hello-world assembly" and include it here.

### Compiler-optimized C, C++
Built with `-O2`, stripped of debug information.

Not changing the program text, just how we invoke it.

### Compiler-optimized Rust
`--release` flag

### Library-trimmed Rust

TODO: Rust and C++(?) both use `libunwind` to walk back stacks on error.

If we use `panic=abort` in Rust, we may be able to cut that down and avoid a dynamic load. For a program mostly used interactively, on the command line, we don't need to care about continuing after panics.


###  musl `libc`: C, C++, Rust
One of the big differences between Golang and these three is static linkage. By default, these languages will dynamically link to the system `libc`; my test machine uses the Debian OS, so they use glibc (GNU `libc`).

[musl `libc`](https://www.musl-libc.org) is a different `libc` implementation, designed to work well with static linking (though it doesn't require it). Does changing the `libc` affect anything?
### Statically-linked musl: C, C++, Rust
Since musl `libc` supports static linking, we can reconfigure our builds to statically-link the resulting binaries.

In theory, this should take off some startup time: the program won't need to invoke the dynamic loader before it gets going.

The downside of static linking is that programs won't pick up `libc` improvements (e.g. security fixes) until rebuilt; and the link time _may_ be higher, though that would be a separate analysis.

### Mustang: `libc`-free Rust
While a `libc` implementation isn't necessarily written in C, both musl and glibc are written in C. A program that links to `libc` accepts that into its memory space - with all the undefined-behaviors and other risks that a C-language program has.[^verified]

Languages like Rust and Golang are designed to be safe-by-default: there isn't "undefined behavior" in the C sense, and getting e.g. a buffer-overflow requires explicitly saying "what I am doing is unsafe". (Literally: the [`unsafe`](https://pkg.go.dev/unsafe) Golang package or [`unsafe`](https://doc.rust-lang.org/std/keyword.unsafe.html) Rust keyword.)

So it's a point of concern, when using Rust, that the Linux default is to include a dependency on `libc`. Your _code_ might be safe, but your _program_ isn't.

There's a couple ways to avoid this. One would be to write the `libc` in Rust: that's what [Relibc](https://gitlab.redox-os.org/redox-os/relibc) is doing. 

The one we're going to try is the Go-like approach:[^gokrazy] build the standard library on top of system calls, rather than on top of `libc` calls. The [Mustang](https://github.com/sunfishcode/mustang) project aims to do this for Linux,[^other-rusts] with the caveat that:

> Mustang isn't about making anything safer, for the foreseeable future. The major libc implementations are extraordinarily well tested and mature. Mustang for its part is experimental and has lots of `unsafe`.

[^verified]: I'm being slightly unfair here: formal verification methods, [runtime checks](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html), [extensive / exhaustive / thorough testing](https://www.sqlite.org/testing.html), and "have a lot of users" can all reduce the prevalence of errors in C programs. Still, each of those backstops adds cost (possibly a lot), while more-recent languages attempt safety as the default.
[^other-rusts]: I'm not sure of what similar efforts look like on other OSes.
[^gokrazy]: As noted above, Golang doesn't use `libc` by default, though usually it will be on a system that includes `libc`. The exception is [`gokrazy`](https://gokrazy.org/), a project where the entire userland is built without `libc`; the "only" remaining C code is the kernel itself.

The main benefit we'd be getting out of Mustang for this test is static linking, without crossing ABI boundaries. Let's see what it does!

### Bytecode caching: Python

The background section of [PEP 3147](https://peps.python.org/pep-3147/) says:

> CPython compiles its source code into “byte code”, and for performance reasons, it caches this byte code on the file system whenever the source file has changes. This makes loading of Python modules much faster because the compilation phase can be bypassed.

The PEP proposes caching these files in a `__pycache__` directory; in the Mercurial trace, we see the Python binary loading these files from cache (great).

TODO: link to section

Running our initial `test.py` file doesn't generate a `__pycache__` directory,
though. Apparently this caching only happens for _imported_ modules- the module
used as `__main__` doesn't get this behavior.

This mostly highlights how unrealistic our example is: a real program like Mercurial will have its loading time dominated by the imported modules rather
than the main module. Since we aren't importing any modules, we can't improve on this count further.

For a more complicated program, is something to keep in mind as an optimization:
if the entry point can as-soon-a-possible jump to an imported module, the
bytecode compiler will have less work to do. Something to try if-and-when we
have a bigger program.

TODO: link to future work

## Batch 2: Results

### By the numbers

### Trace analysis

## Summary
TODO

## Future work

TODO: Generally, adding other dimensions of the analysis; trying to answer more generally "what should I use for my command-line program" rather than just "what starts fastest".

- Better programs: `sha256sum` as a more realistic example. Startup time is less dominant; properties like concurrency support, I/O are more important.
	- Gives goroutines, `async`/`await` features a chance to shine.
	- And requires more code: a `sha256` implementation from _somewhere_.
- Build time measurement - really its own thing.
- Add concurrency and `async` operation
	- No concurrency
	- One OS thread per CPU
	- One OS thread per task
		- Of course, you can't do this in general.
	- One async worker per CPU
		- Goroutine in Golang, future in Rust; consume-from-channel
	- One async worker per task
		- One goroutine per task in Golang
		- One future per task in Rust
