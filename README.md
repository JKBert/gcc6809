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

- **binutils**: $SRC/configure --target=m6809-unknown-elf
- **newlib**:
1. ELF library (multilib, 16/32 bits): $SRC/configure --target=m6809-unknown-elf
2. FLEX-9 library: $SRC/configure --host=m6809-unknown-flex9
3. UniFLEX 6809 library: $SRC/configure --host=m6809-unknown-uniflex
4. SoC 63F09 library (32 bits): $SRC/configure --host=m6809-unknown-soc
- **gcc** (multilib): $SRC/configure --target=m6809-unknown-elf --disable-libssp --without-headers --with-newlib --enable-languages=c,lto,fortran
