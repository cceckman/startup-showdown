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

Let's see what they both have to say about:

- `hg` (Python)
	- Note, `chg` to get around the launch-time problem!
- `git`(C)
- `rg` (Rust)
- `tailscale` (Golang)

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
use std::fmt::println;

fn main() {
  println!("Hello, world!").unwrap();
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
TODO: Our original Python build had a "clean command line" of "clear out `pyc` files".

CPython compiles modules to bytecode, then runs the bytecode. If you re-run a program without changing the source, CPython can skip the "compile to bytecode" step and re-use the cached file.

This is a little bit unfair: producing the bytecode is more similar to the "compilation" step. (If we had Java in the mix, this would be even more obvious: Java has an explicit compile-to-bytecode command, `javac`.) So our "page cache" vs. "non page cache" runs show the effects of both "page cache" and "recompilation."

See this more clearly if we use a "compile" step to run it once; then our "clean" run has the compilation cache, but not the page cache. This is more realistic for a command-line program, and more comparable to the other test cases - we aren't going to change the program between every run, so the `pyc` cache should still be OK to use.
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
