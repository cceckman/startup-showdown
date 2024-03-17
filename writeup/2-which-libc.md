---
author: "Charles Eckman <charles@cceckman.com>"
date: 2024-03-17
mainfont: DejaVuSerif.ttf
sansfont: DejaVuSans.ttf
monofont: DejaVuSansMono.ttf 
mathfont: texgyredejavu-math.otf 
---

# Startup Showdown: Linking `libc`

In the [first group](1-hello-bench.md) of [Startup Showdown](0-outline.md)
experiments, the slowest performers were Golang and Python.

I _think_ all the other languages use the system `libc` and the dynamic loader.
That means that a good portion of the program's logic

## What's a `libc`?

TODO:

-   C language spec defines a bunch of functions that must be provided by the system
-   On Debian and other many other Linuxes, provided by a shared library
    -   On Debian, GNU `libc`
    -   On Alpine, musl libc
    -   On gokrazy... nothing! No C code outside the kernel, unless you bring it!
-   Linux doesn't actually launch "the program": `.INTERP` section says "run the dynamic linker/loader" instead
-   Dynamic loader puts the symbols together
-   Then jump to (where?) in the loaded program

Also, `crt.o`, which is _statically_ linked - part of the compiler.

## Every step of C startup

Let's watch this happening!

TODO: 

-   `strace` breakdown - look at all the steps
-   `ptrace` breakdown - same steps, but count how long they take

## What if `libc` isn't shared?

TODO:

-   Build, but statically linking against the system libc
-   Build, and statically link with LTO
-   Build, statically linking against musl `libc`
    -   ...with LTO
-   Build, dynamically linking aginst musl `libc`

-   Compare file-size for each

