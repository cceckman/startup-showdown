author: "Charles Eckman <charles@cceckman.com>"
date: 2024-02-25
---

# Startup Showdown


When is a program's execution dominated by its startup cost?

How does the answer differ across programming languages?

Why? How do we know?

## The small question

I started this project with a simpler question: if I write myself a little
program to use on the command line, how much time am I wasting waiting for it
to start up? All else being equal, does the choice of programming language
matter?

For example: at my last job, I was using a version of the [Mercurial]
source-control tool. _Perceptually_, it was pretty slow to produce results
(even with [`chg`][chg] enabled); is that my fault (for having a too-large
repository), or can I blame Python?

_Of course_ startup time isn't the only factor in language choice for a project.
There's all sorts of other more-or-less objective considerations (runtime performance,
compile time performance, resource usage), and - often more importantly -
subjective considerations (team/collaborator dynamics, longevity,
system interactions). There's very good reasons to weight those more!

But I don't want to make an _uninformed_ choice, or rely on incorrect
assumptions.

## Computer theory --> computer science

When I started digging in to this, I realized there's a bunch of cool things to
practice and/or learn by investigating it: stuff like experimental design,
debugging and optimization, compiler practice... all the other little fiddly
bits about how languages work.

These posts are my mildly-polished notes about what I tried and what I learned.
**I'm going to be wrong about some things** - sorry! If you have any
corrections - or any tips, clarifications, or other feedback - please do reach
out via [email] or [Mastodon]!

## Chapters

1.  [Hello](1-hello-bench.md):
    As with anything in programming langauges, we'll start with "hello world".
    How long does it take a program to start writing to its standard output?

2.  C and C-adjacent langauges are regarded as "fast"; at least part of that
    comes from sharing `libc.so` across the system. How much impact does a
    shared `libc` have? What about a static `libc`?

    <!-- Some links of relevance:
    https://msfjarvis.dev/posts/building-static-rust-binaries-for-linux/
    https://doc.rust-lang.org/reference/linkage.html
    -->

3.  Languages like C, C++, and Rust aim to have "nothing below" them in terms of
    performance. What's the actual floor- the program with the smallest
    possible startup cost?

4.  What are these programs doing at startup, that's taking up all this time?
    <!-- What does crt.o do? What does the Go runtime do? -->

5.  "Hello world" is not very representative of real programs. Do our results
    line up with a bigger program, like `sha256sum`?

6.  What's the "marginal cost" of different features, like multithreading?

[Mercurial]: https://www.mercurial-scm.org/
[chg]: https://wiki.mercurial-scm.org/CHg
[email]: mailto:charles@cceckman.com
[Mastodon]: https://hachyderm.io/@cceckman
