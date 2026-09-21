# gcc6809

A complete GNU toolchain targeting the Motorola 6809 CPU family and its
custom-silicon successor, the **63F09**:

- **GCC** (C, Fortran, C++...)
- **binutils** (assembler, linker, disassembler)
- **GDB** (debugger)
- **newlib** (C library)

This is not an update of the old, unmaintained `gcc6809` project — it is a
compiler backend, assembler and library port written from scratch, with real
optimization passes, targeting the full 6809/6309/63F09 family.

## What is the 63F09?

The 63F09 is a custom CPU designed in VHDL by Systella, built as a true
hardware extension of the Motorola 6809 — not an emulation or a
reimplementation from a spec sheet, but a real, synthesizable design meant to
run on an FPGA. Full documentation: https://63f09.systella.fr

It sits at the top of a three-level, backward-compatible family:

- **MC6809** — the original 16-bit Motorola CPU (1978): the baseline
  instruction set and register file this whole family builds on.
- **HD6309** — Hitachi's 16-bit, object-code-compatible extension of the
  6809: extra registers (`E`, `F`, forming `W`; `Q` = `D:W`) and additional
  instructions.
- **63F09** — Systella's own extension of the 6309, adding a 32-bit mode on
  top of the existing 16-bit one, a wider register file (`V`, `DS`, and the
  64-bit composite `O` = `Q:V`), hardware 32-bit multiply/divide
  (`MULDU`/`DIVDU`/`DIVQU`), and an optional 64-bit hardware FPU — available
  only when the CPU itself is running in its 32-bit register mode (there is
  no 16-bit-plus-FPU variant). The CPU's own address bus is 32 bits
  wide, matching its address registers; an MMU (in development) will extend
  the *external* address bus to 36 bits, for up to 64 GB of addressable
  memory. Clock speeds up to 600 MHz are targeted — this is meant as a real,
  general-purpose CPU capable of running modern operating systems, not a
  microcontroller.

## What this toolchain produces today

Cross-compiled binaries for:

- **6809** — bare metal, FLEX9, UniFLEX
- **6309** — bare metal, FLEX9, UniFLEX
- **63F09** — bare metal, SoC (system-on-chip development board)

Environment support (bare metal / FLEX9 / UniFLEX / SoC) and CPU submode
(6809 / 6309 / 63F09, 16- or 32-bit) are independent choices: the same
toolchain builds for any combination that makes sense on real hardware.

## Status

Actively developed. GCC, binutils and GDB are functional for all of the
combinations above; the newlib C library port is in progress, environment
by environment.

## Build

### Automated (recommended)

The `Makefile` at the root of this repository drives the entire sequence
below end to end -- binutils, GCC (front-ends only), the ELF newlib
multilib, GCC again (target libraries across every multilib variant), the
libgfortran-multilib fix, and the FLEX9/FLEX9-6309/UniFLEX/UniFLEX-6309/
SoC/SoC-FPU newlib variants -- from three separate, already-unpacked source
trees into one install prefix:

```
make NEWLIB_SRC=/path/to/newlib-x.y.z \
     GCC_SRC=/path/to/gcc-x.y.z \
     BINUTILS_SRC=/path/to/binutils-gdb \
     PREFIX_INSTALL=/path/to/install/prefix
```

Each stage is tracked with a stamp file under `.stamps/`, so re-running
`make` after an interruption or a failure resumes where it left off instead
of starting over; `make clean` removes the build directories (never the
installed prefix or the stamps), `make distclean` also drops the stamps.
Run `make help` for the full variable/target list, or build one piece at a
time instead of everything -- `make binutils`, `make gcc-stage1`,
`make newlib-soc`, `make newlib` (every newlib variant), etc.

### Manual, step by step

What the Makefile above actually runs, kept here as reference and for
building a single piece by hand. `$BINUTILS_SRC`, `$GCC_SRC`, `$NEWLIB_SRC`
and `$PREFIX_INSTALL` are the same four paths the Makefile takes as arguments.

#### binutils

```
mkdir -p $BINUTILS_SRC/build && cd $BINUTILS_SRC/build
$BINUTILS_SRC/configure --target=m6809-unknown-elf --prefix=$PREFIX_INSTALL
make
make install
```

#### newlib (ELF, multilib: 6809/6309/63f09/63f09hf)

Uses the top-level, combined-tree configure (not `newlib/configure`), so
that `config-ml.in` drives the real multilib build.

```
mkdir -p $NEWLIB_SRC/build/elf && cd $NEWLIB_SRC/build/elf
$NEWLIB_SRC/configure --target=m6809-unknown-elf \
    CC_FOR_TARGET=m6809-unknown-elf-gcc \
    AR_FOR_TARGET=m6809-unknown-elf-ar \
    RANLIB_FOR_TARGET=m6809-unknown-elf-ranlib \
    --prefix=$PREFIX_INSTALL
make
make install
```

#### newlib (FLEX9, 6809)

```
mkdir -p $NEWLIB_SRC/build/flex9 && cd $NEWLIB_SRC/build/flex9
$NEWLIB_SRC/newlib/configure --host=m6809-unknown-flex9 \
    CC=m6809-unknown-elf-gcc AR=m6809-unknown-elf-ar \
    AS=m6809-unknown-elf-as RANLIB=m6809-unknown-elf-ranlib \
    CFLAGS='-g -O2' \
    --prefix=$NEWLIB_SRC/build/flex9/install
make
make install
cp -f $NEWLIB_SRC/build/flex9/install/m6809-unknown-flex9/lib/{libc.a,libg.a,libm.a} \
    $PREFIX_INSTALL/m6809-unknown-elf/lib/flex9/
```

#### newlib (FLEX9, 6309)

```
mkdir -p $NEWLIB_SRC/build/flex9-6309 && cd $NEWLIB_SRC/build/flex9-6309
$NEWLIB_SRC/newlib/configure --host=m6809-unknown-flex9 \
    CC=m6809-unknown-elf-gcc AR=m6809-unknown-elf-ar \
    AS=m6809-unknown-elf-as RANLIB=m6809-unknown-elf-ranlib \
    CFLAGS='-g -O2 -m6309' \
    --prefix=$NEWLIB_SRC/build/flex9-6309/install
make
make install
cp -f $NEWLIB_SRC/build/flex9-6309/install/m6809-unknown-flex9/lib/{libc.a,libg.a,libm.a} \
    $PREFIX_INSTALL/m6809-unknown-elf/lib/6309/flex9/
```

#### newlib (UniFLEX, 6809)

```
mkdir -p $NEWLIB_SRC/build/uniflex && cd $NEWLIB_SRC/build/uniflex
$NEWLIB_SRC/newlib/configure --host=m6809-unknown-uniflex \
    CC=m6809-unknown-elf-gcc AR=m6809-unknown-elf-ar \
    AS=m6809-unknown-elf-as RANLIB=m6809-unknown-elf-ranlib \
    CFLAGS='-g -O2' \
    --prefix=$NEWLIB_SRC/build/uniflex/install
make
make install
cp -f $NEWLIB_SRC/build/uniflex/install/m6809-unknown-uniflex/lib/{libc.a,libg.a,libm.a} \
    $PREFIX_INSTALL/m6809-unknown-elf/lib/uniflex/
```

#### newlib (UniFLEX, 6309)

```
mkdir -p $NEWLIB_SRC/build/uniflex-6309 && cd $NEWLIB_SRC/build/uniflex-6309
$NEWLIB_SRC/newlib/configure --host=m6809-unknown-uniflex \
    CC=m6809-unknown-elf-gcc AR=m6809-unknown-elf-ar \
    AS=m6809-unknown-elf-as RANLIB=m6809-unknown-elf-ranlib \
    CFLAGS='-g -O2 -m6309' \
    --prefix=$NEWLIB_SRC/build/uniflex-6309/install
make
make install
cp -f $NEWLIB_SRC/build/uniflex-6309/install/m6809-unknown-uniflex/lib/{libc.a,libg.a,libm.a} \
    $PREFIX_INSTALL/m6809-unknown-elf/lib/6309/uniflex/
```

#### newlib (SoC, 63F09)

```
mkdir -p $NEWLIB_SRC/build/soc && cd $NEWLIB_SRC/build/soc
$NEWLIB_SRC/newlib/configure --host=m6809-unknown-soc \
    CC=m6809-unknown-elf-gcc AR=m6809-unknown-elf-ar \
    AS=m6809-unknown-elf-as RANLIB=m6809-unknown-elf-ranlib \
    CFLAGS='-g -O2 -m63f09' \
    --prefix=$NEWLIB_SRC/build/soc/install
make
make install
cp -f $NEWLIB_SRC/build/soc/install/m6809-unknown-soc/lib/{libc.a,libg.a,libm.a} \
    $PREFIX_INSTALL/m6809-unknown-elf/lib/63f09/soc/
```

#### newlib (SoC, 63F09HF)

```
mkdir -p $NEWLIB_SRC/build/sochf && cd $NEWLIB_SRC/build/sochf
$NEWLIB_SRC/newlib/configure --host=m6809-unknown-sochf \
    CC=m6809-unknown-elf-gcc AR=m6809-unknown-elf-ar \
    AS=m6809-unknown-elf-as RANLIB=m6809-unknown-elf-ranlib \
    CFLAGS='-g -O2 -m63f09hf' \
    --prefix=$NEWLIB_SRC/build/sochf/install
make
make install
cp -f $NEWLIB_SRC/build/sochf/install/m6809-unknown-sochf/lib/{libc.a,libg.a,libm.a} \
    $PREFIX_INSTALL/m6809-unknown-elf/lib/63f09hf/soc/
```

#### gcc

```
mkdir -p $GCC_SRC/build && cd $GCC_SRC/build
$GCC_SRC/configure --target=m6809-unknown-elf --disable-libssp \
    --with-newlib --enable-languages=c,lto,fortran --prefix=$PREFIX_INSTALL
make
make install
```

A plain `make`/`make install` does NOT build libgfortran for the non-default
multilib variants (6309/63f09/63f09hf): unlike libgcc, whose own Makefile
wires its multilib recursion into the ordinary `all` target, libgfortran's
does not, and the top-level Makefile never invokes it either (a real
asymmetry in this GCC version's generated build, not specific to this
port). Run these explicitly after the normal build/install:

```
cd $GCC_SRC/build/m6809-unknown-elf/libgfortran
make all-multi
make install-multi
```

If `make all-multi` visibly does nothing (no recursion into 6309/63f09/...
subdirectories), libgfortran was configured before the cross compiler
reported multilib support and its Makefile still has an empty `MULTIDIRS`.
Fix: re-run `./config.status` (plain, NOT `--recheck`) in the same
directory first -- this both recomputes `MULTIDIRS` and reconfigures the
multilib subdirectories, can take a couple of minutes -- then retry
`make all-multi`:

```
cd $GCC_SRC/build/m6809-unknown-elf/libgfortran
./config.status
make all-multi
make install-multi
```
