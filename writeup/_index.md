---
title: "Startup Showdown"
author: "Charles Eckman <charles@cceckman.com>"
date: 2024-04-08
draft: true
---

When is a program's execution dominated by its startup cost?

How does the answer differ across programming languages?

Why? How do we know?

## The little question {#original}

I use a lot of command-line tools when I'm developing software.
Some are the GNU tools, mostly written in C; some are in
Python, Go, or Rust. (Those happen to be languages I'm familiar with, too!)

Most of the time, I'm running these interactively-- waiting for them
to show me something before I can make my next decision. Most of the time
they're transient: not a daemon that runs in the background, but a process
that exits quickly once it's done.

I get annoyed when my CLI programs are (perceptually) slow.
Waiting for multiple seconds for some output gives me time to think...
and to come up with questions like this one:

> All else being equal, how much does the choice of language impact the
startup cost of the program?

_Of course_ there are a lot of other factors in the speed of the program:
the work the program is doing, how the language maps to hardware, the size
of the task it's invoked for. There's other factors in the startup
too: file caching, system load, dependencies.  And in a lot of cases,
the startup time will be lost in the noise: servers,
clients, compute- or IO-heavy workloads.

But this question hooked my curiousity. I want to know:

- How expensive is "just" startup, independent of the execution speed?
- How do choices made by tool authors (beyond language) affect the startup time?
- Where _is_ the "lost in the noise" boundary?

## From computer theory to computer science

I think investigating these questions offers some neat things to learn and practice.

-   Optimization: Where does the time go? How do we measure it?
-   Experimental design: What variables can be isolated?
-   Languages and libraries: What's going on under the hood of the program?

In the grand scheme, of course, I'm going to spend longer
[answering the question](https://xkcd.com/1205/) than I'll ever save by "optimizing" any tool.
The point is learning, not the outcome.

These posts are my mildly-polished notes about these experiments.
**I'm going to be wrong about some things** -- sorry! If you have any
corrections -- or any tips, clarifications, or other feedback -- please do reach
out via [email] or [Mastodon].

## Sections

1.  [**Hello**](1-hello-bench):

    How long does a program in $language take to start writing to its standard output?

<!--
2.  **Linking and loading**: C and C-adjacent langauges are considered "fast";
    at least part of that comes from sharing `libc` across the system.

    How much impact does a shared `libc` have? What about a static `libc`?

    Some links of relevance:
    https://msfjarvis.dev/posts/building-static-rust-binaries-for-linux/
    https://doc.rust-lang.org/reference/linkage.html

<!--

3.  **Finding the floor**: Languages like C, C++, and Rust aim to have
    "nothing below" them in terms of performance.

    What's the actual floor- the program with the smallest possible startup
    cost?

4.  **Under the hood**:

    What are these programs doing at startup, that's taking up all this time?
    What does crt.o do? What does the Go runtime do?

5.  **But really**: "Hello world" is not very representative of real programs.

    Do our results line up with a bigger program, like `sha256sum`?

6.  **Pay for use**:

    What's the "marginal cost" of different features, like multithreading?

-->

[email]: mailto:charles@cceckman.com
[Mastodon]: https://hachyderm.io/@cceckman

## Acknowledgements

Thanks to Meg, Claire, Nic, and Aditya for reviewing this.

Much of the work for this series was done at [the Recurse Center](https://www.recurse.com/scout/click?t=8238c6d9149cbd0865752e535795d509).
