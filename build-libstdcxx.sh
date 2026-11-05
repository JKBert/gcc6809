#!/bin/bash
# Copyright (C) 2026 Joel Bertrand <joel.bertrand@systella.fr> and Claude (Anthropic).
#
# libstdc++-v3 (libsupc++ included) for ONE 32-bit multilib of the m6809 port; called by the
# libstdcxx-multilib target of the Makefile.
#
#   build-libstdcxx.sh GCC_SRC GCC_BUILD PREFIX TARGET MDIR "FLAGS" [JOBS]
#   e.g. build-libstdcxx.sh ~/gcc ~/gcc/build ~/inst m6809-unknown-elf 63f09hf "-m63f09hf" 5
#
# Why not the top-level multilib recursion (it is switched off with --disable-libstdcxx):
#   * the 16-bit multilibs cannot host libstdc++ (its int, size_t... exceed 16 bits), and their configure
#     probes fail, which would stop the whole recursion at the first failure;
#   * the include/c++ headers that the previous multilib installed in PREFIX are found by the
#     configure probes of the next one (complex.h, fenv.h... answered "no": about 50 wrong results), so
#     each multilib is configured with that directory moved aside.  The headers of all multilibs are
#     identical afterwards (the two config.h are), so the last install wins without harm;
#   * --libdir gets the multilib directory added a second time by the install: the libraries are moved up.
# The configure probes link small programs that pull a large part of newlib: no section-address check and
# huge MEMORY regions (CLAUDE.md of binutils-gdb, revision 62).
set -e
GCC_SRC=$1; GCC_BUILD=$2; PREFIX=$3; TARGET=$4; MDIR=$5; FLAGS=$6; JOBS=${7:-5}
D=$GCC_BUILD/$TARGET/$MDIR/libstdc++-v3
INC=$PREFIX/$TARGET/include/c++
export PATH=$PREFIX/bin:$PATH
LDF="-Wl,--no-check-sections -Wl,--defsym,__ram_length=0x10000000 -Wl,--defsym,__rom_length=0x10000000"

[ -d "$INC" ] && mv "$INC" "$INC.hold"
trap '[ -d "$INC.hold" ] && { [ -d "$INC" ] && rm -rf "$INC.hold" || mv "$INC.hold" "$INC"; }' EXIT

rm -rf "$D"; mkdir -p "$D"; cd "$D"
CONFIG_SITE=/dev/null "$GCC_SRC/libstdc++-v3/configure" \
  --host=$TARGET --build=$(sh "$GCC_SRC/config.guess") --target=$TARGET \
  --prefix="$PREFIX" --libdir="$PREFIX/$TARGET/lib/$MDIR" \
  --with-newlib --disable-shared --enable-static --disable-nls --disable-libstdcxx-pch \
  --disable-libstdcxx-verbose --disable-multilib --with-gxx-include-dir="$INC/$(cat "$GCC_SRC/gcc/BASE-VER")" \
  CC="$TARGET-gcc $FLAGS" CXX="$TARGET-g++ $FLAGS" CFLAGS="-g -O2" CXXFLAGS="-g -O2" LDFLAGS="$LDF" \
  AR=$TARGET-ar RANLIB=$TARGET-ranlib NM=$TARGET-nm
# /home is NFS: a transient "readdir: Erreur d'entree/sortie" kills a parallel make now and then; a second
# run resumes where it stopped.
make -j"$JOBS" || make -j"$JOBS"
make install
# install put the libraries in lib/MDIR/MDIR: one level up
L=$PREFIX/$TARGET/lib/$MDIR
if [ -d "$L/$MDIR" ]; then mv "$L/$MDIR"/* "$L"/ && rmdir "$L/$MDIR"; fi
