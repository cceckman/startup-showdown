---
title: "Startup Showdown 2 - Linking and Loading"
draft: true
author: "Charles Eckman <charles@cceckman.com>"
date: 2024-03-17
---

In the [first group](../1-hello-bench) of [Startup Showdown](../)
experiments, we saw a spread of startup times: from C (sub-millisecond)
to Python (tens of milliseconds).

What gives?

## Three interpretations

Let's start by looking at what _actually_ runs when you start a program.

Of [the programs we're testing](https://github.com/cceckman/startup-showdown/tree/main/sut),
there's two obvious "executable" formats we can see:

- Rust, C, C++, and Go all use _binary_ formats. We have to compile the program from source -- in this case, into the [Executable and Linkable Format (ELF)](https://man7.org/linux/man-pages/man5/elf.5.html)) -- and then run the result.
- Python and shell use _textual_ formats. We can directly execute the source code.

The Linux kernel can understand multiple executable formats by looking
for specific ("magic") values at particular offsets. For instance:[^binfmt-misc]

-   The ELF format starts with the magic string `\x7fELF` (at offset 0)
-   Scripts start with `#!`

[^binfmt-misc]: As far as I can tell, these two are built-in to the kernel.
    TODO: Find the source, write a tangent?
    The [`binfmt-misc`](https://docs.kernel.org/admin-guide/binfmt-misc.html) feature
    lets you register other formats: for a neat trick, you can set up an [x86 system
    to run ARM binaries](https://wiki.debian.org/QemuUserEmulation) or vice versa,
    [Rosetta-style](https://en.wikipedia.org/wiki/Rosetta_(software)).

Both of these file types can name an **interpreter**: a program to launch
"instead of" treating this as a binary. 

### "Interpret" to load libraries

Let's see how a "low-level" language uses an interpreter!

The [`readelf`](https://man7.org/linux/man-pages/man1/readelf.1.html)
tool is great for peeking into binaries. In this case, we're looking for
a `PT_INTERP` program header. Per the
[`elf(5)` man page](https://man7.org/linux/man-pages/man5/elf.5.html):

>  `PT_INTERP`: The array element specifies the location and
>  size of a null-terminated pathname to invoke as
>  an interpreter.  This segment type is meaningful
>  only for executable files (though it may occur
>  for shared objects).  However it may not occur
>  more than once in a file.  If it is present, it
>  must precede any loadable segment entry.

We can see in the C binary:[^commit-1]

[^commit-1]: My repository is sitting at commit `5576338b`.

```shell
∵ ./do -c sut/5-c/test >/dev/null 2>&1
∵ readelf --wide --program-headers sut/5-c/test

Elf file type is DYN (Position-Independent Executable file)
Entry point 0x1050
There are 13 program headers, starting at offset 64

Program Headers:
  Type           Offset   VirtAddr           PhysAddr           FileSiz  MemSiz   Flg Align
  PHDR           0x000040 0x0000000000000040 0x0000000000000040 0x0002d8 0x0002d8 R   0x8
  INTERP         0x000318 0x0000000000000318 0x0000000000000318 0x00001c 0x00001c R   0x1
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
  LOAD           0x000000 0x0000000000000000 0x0000000000000000 0x000648 0x000648 R   0x1000
  LOAD           0x001000 0x0000000000001000 0x0000000000001000 0x000171 0x000171 R E 0x1000
  LOAD           0x002000 0x0000000000002000 0x0000000000002000 0x0000ec 0x0000ec R   0x1000
  LOAD           0x002dc0 0x0000000000003dc0 0x0000000000003dc0 0x000258 0x000260 RW  0x1000
  DYNAMIC        0x002dd0 0x0000000000003dd0 0x0000000000003dd0 0x0001f0 0x0001f0 RW  0x8
  NOTE           0x000338 0x0000000000000338 0x0000000000000338 0x000020 0x000020 R   0x8
  NOTE           0x000358 0x0000000000000358 0x0000000000000358 0x000044 0x000044 R   0x4
  GNU_PROPERTY   0x000338 0x0000000000000338 0x0000000000000338 0x000020 0x000020 R   0x8
  GNU_EH_FRAME   0x002014 0x0000000000002014 0x0000000000002014 0x00002c 0x00002c R   0x4
  GNU_STACK      0x000000 0x0000000000000000 0x0000000000000000 0x000000 0x000000 RW  0x10
  GNU_RELRO      0x002dc0 0x0000000000003dc0 0x0000000000003dc0 0x000240 0x000240 R   0x1

 Section to Segment mapping:
  Segment Sections...
   00
   01     .interp
   02     .interp .note.gnu.property .note.gnu.build-id .note.ABI-tag .hash .gnu.hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt
   03     .init .plt .plt.got .text .fini
   04     .rodata .eh_frame_hdr .eh_frame
   05     .init_array .fini_array .dynamic .got .got.plt .data .bss
   06     .dynamic
   07     .note.gnu.property
   08     .note.gnu.build-id .note.ABI-tag
   09     .note.gnu.property
   10     .eh_frame_hdr
   11
   12     .init_array .fini_array .dynamic .got
∴ 0 startup-showdown:loading…startup-showdown
```

Lots of information there, but `readelf` is very helpful and calls out:

```
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
```

The same is true of the C++ and Rust binaries... and of `bash`, `dash`, `zsh`, and Python:

```
∵ ./do sut/6-cpp/test sut/7-rust/test >/dev/null 2>&1
∴ 0 startup-showdown:loading…startup-showdown
∵ for f in \
  sut/6-cpp/test sut/7-rust/test \
  /usr/bin/dash /usr/bin/bash /usr/bin/zsh \
  /usr/bin/python3
do
  readelf --program-headers $f \
  | grep "Requesting program interpreter" \
  || { echo >&2 "Missing from $f" }
done
```

Outputs:
```
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
```

Here, [`man ld-linux.so`](https://man7.org/linux/man-pages/man8/ld.so.8.html)
starts our explanation: it's the _dynamic linker_, responsible for combining
executables and _shared libraries_ in memory.

There's a lot more about dynamic linking on the internet. It's a pretty complicated
topic -- I want learn more about it, but for this article, I'll just go with the outlines.

All these executables (written in C/C++/Rust) rely on some number of shared libraries, that have
common routines like "open a file" or "print formatted output". The system tries
to save memory by loading these shared libraries into memory only once, and using that
copy for any processes that need the shared library.

But for various reasons, the shared library may not be in the same address in each process.
And the executable (what we wrote) won't necessarily know that address when we're compiling it --
the compiler[^linker] has left "empty slots" where these shared-library calls show up.
Something needs to:

1.  Pick adresses for the shared libraries
2.  Load the shared libraries
3.  Fill the "slots" in the executable, then
4.  Start the executable[^defer]

[^linker]: ...well, the static linker; but we aren't invoking it separately in these builds. Yet.

And that "something" is `ld-linux.so`.

It looks at the ELF files to find the shared libraries they request:

```shell
for f in sut/5-c/test sut/6-cpp/test sut/7-rust/test
do
  echo "${f}: "
  ldd $f
done
```

Outputs: [^ldd]

[^ldd]: I'm using `ldd` here because its output is nicer. It looks like `ldd` is pulling from the "dynamic section"
of the ELF; `readelf --dynamic <binary>` shows `DT_NEEDED` entries for each shared library.

```
sut/5-c/test:
        linux-vdso.so.1 (0x00007ffc98276000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f92f48ff000)
        /lib64/ld-linux-x86-64.so.2 (0x00007f92f4af1000)
sut/6-cpp/test:
        linux-vdso.so.1 (0x00007ffd34fba000)
        libstdc++.so.6 => /lib/x86_64-linux-gnu/libstdc++.so.6 (0x00007facab000000)
        libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007facab302000)
        libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1 (0x00007facab2e2000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007facaae1f000)
        /lib64/ld-linux-x86-64.so.2 (0x00007facab3f2000)
sut/7-rust/test:
        linux-vdso.so.1 (0x00007ffc3abee000)
        libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1 (0x00007f74c676a000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f74c6589000)
        /lib64/ld-linux-x86-64.so.2 (0x00007f74c67ee000)
```

It will also try to find the functions to be resolved:

```shell
∵ readelf --relocs sut/5-c/test

Relocation section '.rela.dyn' at offset 0x570 contains 8 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000003dc0  000000000008 R_X86_64_RELATIVE                    1130
000000003dc8  000000000008 R_X86_64_RELATIVE                    10f0
000000004010  000000000008 R_X86_64_RELATIVE                    4010
000000003fc0  000100000006 R_X86_64_GLOB_DAT 0000000000000000 __libc_start_main@GLIBC_2.34 + 0
000000003fc8  000200000006 R_X86_64_GLOB_DAT 0000000000000000 _ITM_deregisterTM[...] + 0
000000003fd0  000400000006 R_X86_64_GLOB_DAT 0000000000000000 __gmon_start__ + 0
000000003fd8  000500000006 R_X86_64_GLOB_DAT 0000000000000000 _ITM_registerTMCl[...] + 0
000000003fe0  000600000006 R_X86_64_GLOB_DAT 0000000000000000 __cxa_finalize@GLIBC_2.2.5 + 0

Relocation section '.rela.plt' at offset 0x630 contains 1 entry:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000004000  000300000007 R_X86_64_JUMP_SLO 0000000000000000 printf@GLIBC_2.2.5 + 0
```

and arrange for them to be resolved when needed.[^c-relocs][^deferred]

There's a lot more detail about this procedure in [_System V Application Binary Interface - AMD64 Architecture Processor Supplement_](https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf): what the relocation types mean and how they're represented.
I think it's enough for us to say here:

Linux starts `ld.linux.so` instead of our binary. `ld-linux.so` reads the target ELF, resolves any shared-library dependencies, and then starts the program we built.

TODO: Didn't Drepper have a good guide to this? Yes: https://www.akkadia.org/drepper/dsohowto.pdf

TODO: What's the difference between these two sections, `.rela.dyn` and `.rela.plt`? "imports" and "exports"? SysV document talks about Procedure Linkage Table: "Redirects position-independent function calls to absolute locations"...
Global Offset Table. PLT is shared, uses GOT offsets -> executable text is still "shared"

[^c-relocs]: I've only shown the relocations for the C program here. The C++ and Rust programs include many more symbols in the `.rela.dyn` tables.
[^deferred]: [`man ld`](https://linux.die.net/man/1/ld) has an interesting tidbit, under the documentation for `-z lazy`:
    > When generating an executable or shared library, mark it to tell the dynamic linker to defer function call resolution to the point when the function is called (lazy binding), rather than at load time.  Lazy binding is the default.

    This shows up in [`man dlopen`](https://linux.die.net/man/3/dlopen), the manual call for loading shared libraries:

    > `RTLD_LAZY`: Perform lazy binding. Only resolve symbols as the code that references them is executed. If the symbol is never referenced, then it is never resolved. (Lazy binding is only performed for function references; references to variables are always immediately bound when the library is loaded.) 

    So by default, `ld-linux.so` will wait until the function is called to look it up. Good if there are a lot of unused
    symbol references; otherwise, eh.

### No interpreter

It doesn't have to be this way! There are ways to compile[^link] C/C++/Rust
without dynamic linking - we'll try this [below](#unsharing). We'd lose the
"shared"ness of the shared libraries -- we might have multiple copies of the
same function in memory, in different processes -- but we'd skip a step at
startup.

[^link]: ...well, link, same as above.

Before we try that -- what would that look like, a _statically linked_ binary?

Golang does this already, by default! Our Go binary is "not a dynamic executable",
and doesn't have any dynamic info or an `INTERP`reter:

```shell
∵ ./do sut/8-golang/test >/dev/null 2>&1
∵ ldd sut/8-golang/test
        not a dynamic executable
∴ 1
∵ readelf --file-header sut/5-c/test | grep Type
  Type:                              DYN (Position-Independent Executable file)
∴ 0 
∵ readelf --file-header sut/8-golang/test | grep Type
  Type:                              EXEC (Executable file)
∴ 0 
∵ readelf --program-headers --dynamic sut/8-golang/test

Elf file type is EXEC (Executable file)
Entry point 0x45dd60
There are 6 program headers, starting at offset 64

Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x0000000000400040 0x0000000000400040
                 0x0000000000000150 0x0000000000000150  R      0x1000
  NOTE           0x0000000000000f9c 0x0000000000400f9c 0x0000000000400f9c
                 0x0000000000000064 0x0000000000000064  R      0x4
  LOAD           0x0000000000000000 0x0000000000400000 0x0000000000400000
                 0x000000000007afe3 0x000000000007afe3  R E    0x1000
  LOAD           0x000000000007b000 0x000000000047b000 0x000000000047b000
                 0x0000000000098cf8 0x0000000000098cf8  R      0x1000
  LOAD           0x0000000000114000 0x0000000000514000 0x0000000000514000
                 0x0000000000009680 0x000000000003b2f0  RW     0x1000
  GNU_STACK      0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x0000000000000000 0x0000000000000000  RW     0x8

 Section to Segment mapping:
  Segment Sections...
   00
   01     .note.go.buildid
   02     .text .note.go.buildid
   03     .rodata .typelink .itablink .gosymtab .gopclntab
   04     .go.buildinfo .noptrdata .data .bss .noptrbss
   05

There is no dynamic section in this file.
∴ 0
```

When Linux starts this, it doesn't need to deal with `ld-linux.so`; it just needs to load
these segments into memory, and start from there.

### "Interpret" the source

The other "interpretation" path is via a "shebang" (hash-bang, `#!`) line, which names
another program (and arguments) to start. This is used for scripts, like shell and Python.

TODO: Find this code in the kernel

As far as the shells go (`dash`, `bash`, `zsh`): These are first and foremost based on interactive use.
I _think_ what these do is just read the input file a line at a time, and treat it more-or-less
like someone is at the console. TODO: Citation needed! Look at the code!

Python is a little trickier: it can be used interactively (just run `python3`), but it's also
designed to be performant as an application runtime. The reference Python implementation,
CPython, handles source in several stages: [a compiler](https://devguide.python.org/internals/compiler/)
turns the source Python into bytecode, which is then [interpreted](https://devguide.python.org/internals/interpreter/).

This may go partway to explaining the performance difference between the shells and Python:
Python is doing more up-front work before getting started. Good for real programs, but bad for our toy!

But since we're looking at linkage in this post- what linkages do these _interpreters_ have?

```shell
for f in /usr/bin/dash /usr/bin/bash /usr/bin/zsh /usr/bin/python3
do
    echo "$f: "
    ldd $f
done
```

Outputs:

```
/usr/bin/dash:
        linux-vdso.so.1 (0x00007fffb83bb000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f7b1cad4000)
        /lib64/ld-linux-x86-64.so.2 (0x00007f7b1cce3000)
/usr/bin/bash:
        linux-vdso.so.1 (0x00007fffe11f8000)
        libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6 (0x00007fe8b4042000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007fe8b3e61000)
        /lib64/ld-linux-x86-64.so.2 (0x00007fe8b41c1000)
/usr/bin/zsh:
        linux-vdso.so.1 (0x00007ffd62152000)
        libcap.so.2 => /lib/x86_64-linux-gnu/libcap.so.2 (0x00007f1009115000)
        libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6 (0x00007f10090e2000)
        libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f1009003000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f1008e22000)
        /lib64/ld-linux-x86-64.so.2 (0x00007f1009215000)
/usr/bin/python3:
        linux-vdso.so.1 (0x00007ffcdf79e000)
        libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007fd99476d000)
        libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007fd99474e000)
        libexpat.so.1 => /lib/x86_64-linux-gnu/libexpat.so.1 (0x00007fd994723000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007fd994542000)
        /lib64/ld-linux-x86-64.so.2 (0x00007fd994858000)
```

Note that _among the shells_, the number of shared libraries matches our ranking from [part 1](../1-hello):[^ish] `dash` is fastest (and has the fewest shared libraries), then `bash`, then `zsh`. Coincidence? Maybe...

[^ish]: In one case -- `no-cache` on the server - `zsh` outperformed `bash`. I haven't computed the statistical power of these tests; I'm not sure if "bash and zsh are close" and that's just nois, or if this is pointing to something deeper about which libraries are used, or something else.

## The shared-library advantage

TODO:

Running tests via system shell (`dash`), inside my shell session (`zsh`)

Linking against system `libc` -> already in memory, even in `no-cache` case

Full trace shows: which libraries have to be faulted in?

## Unsharing

The above suggests a few comparisons; how do these stack up?

1.  Dynamically-linked _shared library_: Costs of dynamic linking, benefits of sharing
2.  Dynamically-linked _rare library_: Cost of dynamic linking, no benefits of sharing
3.  Statically-linked library: No costs of dynamic linking, no benefits of sharing

(1) is our baseline. We can make (2) happen by playing some tricks during compilation and runtime;
and we can make (3) happen by passing some additional flags.

