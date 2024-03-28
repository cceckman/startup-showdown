---
title: "Startup Showdown"
author: "Charles Eckman <charles@cceckman.com>"
date: 2024-03-28
---

When is a program's execution dominated by its startup cost?

How does the answer differ across programming languages?

Why? How do we know?

## The little question {#original}

I use a lot of command-line tools, interactively and transiently.
Some are the GNU tools, mostly written in C; some are in
Python, Go, or Rust. (Those happen to be languages I'm familiar with, too!)

Not too long ago, I was annoyed with one: it seemed to take a long time
to produce any output. I couldn't blame this on anything particular,
but it got me wondering:

All else being equal, how much does the choice of language impact the
startup cost of the program?

_Of course_ startup time is not the only contributor to latency; and _of course_
latency is not just a property of the language. Still, I write some tools for
myself: I want to know how much time the startup _does_ take, to weigh it accordingly.

## Computer theory --> computer science

I realized that behind this question, there's some cool things to learn and
practice.

-   Optimization: Where does the time go? How do we measure it?
-   Experimental design: What variables are/aren't isolated?
-   Languages and libraries: What's going on under the hood of the program?

In the grand scheme, of course, I'm going to spend longer
[answering the question](https://xkcd.com/1205/) than I'd ever save.
But I'm expecting to learn from the process!

These posts are my mildly-polished notes about these experiments.
**I'm going to be wrong about some things** - sorry! If you have any
corrections - or any tips, clarifications, or other feedback - please do reach
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

Thanks to Meg and Claire for reviewing this.

