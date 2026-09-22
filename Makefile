# Top-level bootstrap Makefile for the m6809/63F09 GNU toolchain --
# binutils + GCC (C, Fortran) + newlib (ELF multilib: 6809/6309/63f09/
# 63f09hf, plus the FLEX9/UniFLEX/SoC environment C libraries) -- built
# from three separate source trees into one install prefix.
#
# Usage:
#   make NEWLIB_SRC=/path/to/newlib-x.y.z \
#        GCC_SRC=/path/to/gcc-x.y.z \
#        BINUTILS_SRC=/path/to/binutils-gdb \
#        PREFIX_INSTALL=/path/to/install/prefix
#
# Optional (defaults shown):
#   TARGET=m6809-unknown-elf
#   LANGUAGES=c,lto,fortran
#   JOBS=5
#
# This mirrors the build recipe in this repo's own README.md:
#   1. binutils
#   2. GCC, first pass (all-gcc/install-gcc only) -- just enough to get
#      a working $(TARGET)-gcc to build newlib with, no target libc
#      assumed yet.
#   3. newlib, ELF multilib (6809/6309/63f09/63f09hf) -- the C library
#      GCC's own target libraries (libgcc, libgfortran) build against.
#   4. GCC, second pass (plain `make`/`make install`) -- now that
#      newlib exists, this builds and installs libgcc/libgfortran for
#      every multilib variant, plus the libgfortran-multilib fix the
#      README flags as a real, non-obvious gotcha in this GCC tree
#      (libgfortran's own Makefile does not wire multilib recursion
#      into the ordinary all/install targets the way libgcc's does).
#   5. newlib again, once per environment (FLEX9, FLEX9/6309, UniFLEX,
#      UniFLEX/6309, SoC, SoC/FPU) -- each its own private, non-multilib
#      newlib build (subdir configure, --host=m6809-unknown-<env>),
#      with just its libc.a/libg.a/libm.a copied into
#      $(PREFIX_INSTALL)/$(TARGET)/lib/<multilib-dirname>/<env>/ afterwards.
#      These are NOT part of GCC's own multilib mechanism (GCC's
#      multilib only knows about the CPU variants, not the
#      environment) -- environment selection stays a manual -L choice
#      at link time, same as crt0 selection elsewhere in this project.
#
# Each stage is tracked with a stamp file under .stamps/, so re-running
# `make` after an interruption or a failure resumes where it left off
# instead of starting over. `make clean` removes all the build
# directories (never the installed prefix or the stamps); `make
# distclean` also drops the stamps, forcing a full rebuild.

SHELL := /bin/bash

# ---------------------------------------------------------------------
# Configuration -- safe to evaluate with no source paths set, so that
# "make help" always works.
# ---------------------------------------------------------------------
TARGET    ?= m6809-unknown-elf
LANGUAGES ?= c,lto,fortran
JOBS      ?= 5

MAKE_J := $(MAKE) -j$(JOBS)

# Stamp files tracking progress live next to this Makefile, not inside
# the source trees.
STAMP_DIR := $(CURDIR)/.stamps

# ---------------------------------------------------------------------
# Required inputs -- everything below depends on these, so it is all
# skipped (and left undefined) for "make help".
# ---------------------------------------------------------------------
REQUIRED_VARS := NEWLIB_SRC GCC_SRC BINUTILS_SRC PREFIX_INSTALL
ifneq ($(MAKECMDGOALS),help)
$(foreach v,$(REQUIRED_VARS),$(if $($(v)),,$(error $(v) is not set -- run "make help")))

# override: these come in as "command line" variables (make VAR=value on
# the invocation) -- that origin beats a plain ":=" inside the makefile,
# which GNU Make otherwise silently ignores, leaving the ORIGINAL,
# possibly-relative value in place. Real bug hit in practice: run from a
# build/ directory with e.g. BINUTILS_SRC=../binutils-gdb, every path
# below stayed relative to wherever `make` was invoked from -- harmless
# until a recipe `cd`s into a build directory first ("cd $(BINUTILS_BUILD)
# && $(BINUTILS_SRC)/configure ..."), at which point the very same
# relative path now resolves from the NEW directory instead, one level
# too deep ("../binutils-gdb/build/../binutils-gdb/configure: no such
# file"). `override` makes the ":=" below win regardless of where the
# variable came from, so every path is absolute before any recipe runs.
override NEWLIB_SRC      := $(abspath $(NEWLIB_SRC))
override GCC_SRC         := $(abspath $(GCC_SRC))
override BINUTILS_SRC    := $(abspath $(BINUTILS_SRC))
override PREFIX_INSTALL  := $(abspath $(PREFIX_INSTALL))

# NOT called "INSTALL": real bug hit in practice under that name --
# `INSTALL` is also the POSIX/autoconf-reserved name for the install
# PROGRAM (normally "/usr/bin/install -c", substituted by
# AC_PROG_INSTALL, which only searches for one when $INSTALL is EMPTY in
# its environment). A command-line-origin make variable isn't just
# exported into a plain subprocess's environment (`unexport` alone
# stops that) -- it's ALSO encoded into MAKEFLAGS, which GNU Make keeps
# exported regardless (the same channel -j/-k survive recursion
# through), and every child `make` at every depth of binutils-gdb's own
# internal bfd/opcodes/gas/ld/libsframe/... recursion re-parses
# MAKEFLAGS at startup and reconstructs the variable as freshly given on
# ITS OWN command line -- right past that child's own correctly-computed
# "INSTALL = /usr/bin/install -c". Confirmed directly in a real build's
# libsframe/config.log ("checking for a BSD-compatible install ...
# result: ." instead of a real path), and reproduced as far down as
# "make install" trying to run "." (the current-directory shell
# built-in) as the install program. Renaming the variable sidesteps the
# whole problem instead of fighting GNU Make's propagation rules.
#
# MAKEOVERRIDES (the command-line-variable portion MAKEFLAGS is built
# from) is still cleared below, as cheap defense in depth: none of this
# file's own command-line variables need to reach any child
# configure/make -- everything is passed explicitly (--prefix=...,
# CC=..., and so on) -- so nothing legitimate is lost by keeping every
# one of them from leaking into a nested autoconf-based build this way,
# whatever it happens to be named.
MAKEOVERRIDES :=

# Build directories live inside each source tree, matching this
# project's own convention (see README.md, and gcc-16.2.0/build,
# binutils-gdb/build elsewhere in this project). Each newlib environment
# variant (ELF multilib, FLEX9, FLEX9/6309, UniFLEX, UniFLEX/6309, SoC,
# SoC/FPU) gets its own build/<name> subdirectory of $(NEWLIB_SRC), same
# as README.md's own "Create $NEWLIB_SRC/build/<name>" steps.
BINUTILS_BUILD  := $(BINUTILS_SRC)/build
GCC_BUILD       := $(GCC_SRC)/build
NEWLIB_ELF_BUILD := $(NEWLIB_SRC)/build/elf

# TARGET-prefixed cross tools, available once binutils + the first GCC
# pass are installed -- used to build newlib, and needed on PATH for
# GCC's own as/ld auto-detection.
CROSS_BIN    := $(PREFIX_INSTALL)/bin
CROSS_GCC    := $(CROSS_BIN)/$(TARGET)-gcc
CROSS_AR     := $(CROSS_BIN)/$(TARGET)-ar
CROSS_AS     := $(CROSS_BIN)/$(TARGET)-as
CROSS_RANLIB := $(CROSS_BIN)/$(TARGET)-ranlib

export PATH := $(CROSS_BIN):$(PATH)

# Real bug hit in practice: on a Debian-family host, /bin/sh is dash,
# which the libtool scripts config-ml.in generates for each multilib
# subdirectory's target libraries do NOT all tolerate consistently.
# libtool's own func_append optimizes to "eval \"$1+=\$2\"" (a bash-ism
# dash's eval rejects outright, "eval: compile_command+=: not found")
# whenever the configuring shell was detected to support it -- and it
# WAS, consistently, everywhere except one specific path: libgfortran's
# own multilib recursion (config-ml.in's secondary "all-multi"/
# "install-multi" mechanism, needed at all only because -- see
# libgfortran-multilib's own comment below -- libgfortran's Makefile,
# unlike libgcc's or libquadmath's, doesn't wire multilib recursion
# into the ordinary all/install targets). That path's own SHELL
# computation lands on plain "/bin/sh" in the generated
# <multilibdir>/libgfortran/Makefile, disagreeing with the "/bin/bash"
# every OTHER target library's multilib Makefile (including
# libgfortran's own top, non-multilib one) correctly gets from the very
# same build -- confirmed directly by comparing their generated
# Makefiles' own "SHELL = ..." lines side by side. CONFIG_SHELL is the
# standard, universal autoconf mechanism for pinning down exactly this
# choice through every configure invocation a build makes, nested ones
# included; exporting it here is cheap and closes the gap at the root
# instead of chasing it through config-ml.in's own logic.
export CONFIG_SHELL := /bin/bash

COMMON_CONFIGURE_FLAGS := --disable-nls --disable-werror

# gdb/sim/readline/gprofng are not needed to build or use the compiler
# itself -- skipped to keep this build scoped and to avoid pulling in
# their extra host dependencies (ncurses, python, ...). Harmless if
# this tree doesn't recognize one of these flags (autoconf just warns).
BINUTILS_CONFIGURE_FLAGS := \
	--target=$(TARGET) \
	--prefix=$(PREFIX_INSTALL) \
	--disable-gdb --disable-sim --disable-readline --disable-gprofng \
	$(COMMON_CONFIGURE_FLAGS)

# --with-newlib (not --without-headers): matches README.md's own proven
# flags -- GCC's bundled freestanding headers are enough for the first
# "all-gcc" pass, no target libc needs to exist yet.
GCC_CONFIGURE_FLAGS := \
	--target=$(TARGET) \
	--prefix=$(PREFIX_INSTALL) \
	--enable-languages=$(LANGUAGES) \
	--with-newlib \
	--disable-libssp \
	$(COMMON_CONFIGURE_FLAGS)

# Top-level combined-tree newlib configure (not newlib/configure), so
# that libgloss/config-ml.in drive the real 6809/6309/63f09/63f09hf
# multilib build -- see README.md's "newlib (multilib)" section.
NEWLIB_ELF_CONFIGURE_FLAGS := \
	--target=$(TARGET) \
	--prefix=$(PREFIX_INSTALL) \
	CC_FOR_TARGET=$(CROSS_GCC) \
	AR_FOR_TARGET=$(CROSS_AR) \
	RANLIB_FOR_TARGET=$(CROSS_RANLIB)

LIBGFORTRAN_BUILD := $(GCC_BUILD)/$(TARGET)/libgfortran

# Environment-specific newlib variants (README.md's "newlib (Flex9 ...)"
# / "(UniFLEX ...)" / "(SoC ...)" sections): each is its own private,
# non-multilib build via newlib/configure --host=m6809-unknown-<env>
# (NOT the top-level combined configure the ELF multilib build above
# uses -- these environments are not GCC multilib variants, so there is
# no config-ml.in recursion to drive here), installed to a private
# staging prefix inside its own build directory, then just its three
# libraries copied into the shared install tree. One (name, --host,
# extra CFLAGS, destination subpath under lib/) tuple per variant,
# copied verbatim from README.md.
#
#   name          host                       extra cflags   dest subpath under $(PREFIX_INSTALL)/$(TARGET)/lib
# "NONE" stands in for "no extra CFLAGS" -- $(word ...) below silently
# collapses consecutive separators, so a genuinely empty field would
# shift every field after it; stripped back out where CFLAGS is built.
NEWLIB_ENV_SPECS := \
	flex9|m6809-unknown-flex9|NONE|flex9 \
	flex9-6309|m6809-unknown-flex9|-m6309|6309/flex9 \
	uniflex|m6809-unknown-uniflex|NONE|uniflex \
	uniflex-6309|m6809-unknown-uniflex|-m6309|6309/uniflex \
	soc|m6809-unknown-soc|-m63f09|63f09/soc \
	sochf|m6809-unknown-sochf|-m63f09hf|63f09hf/soc

NEWLIB_ENV_NAMES := $(foreach s,$(NEWLIB_ENV_SPECS),$(word 1,$(subst |, ,$(s))))
endif

.PHONY: all help print-config \
	binutils gcc-stage1 newlib newlib-elf gcc-stage2 libgfortran-multilib \
	clean distclean \
	$(NEWLIB_ENV_NAMES:%=newlib-%)

all: libgfortran-multilib newlib
	@echo ""
	@echo "Toolchain installed under $(PREFIX_INSTALL)."
	@echo "Add $(CROSS_BIN) to PATH, then e.g.:"
	@echo "  $(TARGET)-gcc --print-multi-lib"

help:
	@echo "Usage:"
	@echo "  make NEWLIB_SRC=<path> GCC_SRC=<path> BINUTILS_SRC=<path> PREFIX_INSTALL=<path>"
	@echo ""
	@echo "Optional variables (current/default value shown):"
	@echo "  TARGET=$(TARGET)"
	@echo "  LANGUAGES=$(LANGUAGES)"
	@echo "  JOBS=$(JOBS)"
	@echo ""
	@echo "Targets: all (default), binutils, gcc-stage1, gcc-stage2,"
	@echo "         libgfortran-multilib, newlib (all variants below),"
	@echo "         newlib-elf, newlib-flex9, newlib-flex9-6309,"
	@echo "         newlib-uniflex, newlib-uniflex-6309, newlib-soc,"
	@echo "         newlib-sochf, clean, distclean, print-config"

print-config:
	@echo "NEWLIB_SRC       = $(NEWLIB_SRC)"
	@echo "GCC_SRC          = $(GCC_SRC)"
	@echo "BINUTILS_SRC     = $(BINUTILS_SRC)"
	@echo "PREFIX_INSTALL   = $(PREFIX_INSTALL)"
	@echo "TARGET           = $(TARGET)"
	@echo "LANGUAGES        = $(LANGUAGES)"
	@echo "BINUTILS_BUILD   = $(BINUTILS_BUILD)"
	@echo "GCC_BUILD        = $(GCC_BUILD)"
	@echo "NEWLIB_ELF_BUILD = $(NEWLIB_ELF_BUILD)"
	@echo "NEWLIB_ENV_NAMES = $(NEWLIB_ENV_NAMES)"

$(STAMP_DIR) $(BINUTILS_BUILD) $(GCC_BUILD) $(NEWLIB_ELF_BUILD):
	mkdir -p $@

# Always-out-of-date prerequisite, the standard GNU Make idiom for "make
# this recipe run every time, regardless of its own stamp's mtime" --
# used below on binutils'/gcc's own build+install steps only (their
# SOURCE trees have real, correct per-file Make dependencies already,
# so re-invoking them is always fast and safe when nothing changed);
# never on newlib's or gcc-stage2's, which invoke the cross-compiler as
# an opaque external program their own Makefiles have no way to notice
# changed -- see those rules' own comments for how staleness is
# detected for them instead.
.PHONY: FORCE
FORCE:

# Real installed-tool files, not witness stamps: everything below that
# needs to notice "the cross toolchain actually changed" (not just
# "this Makefile's own gcc-stage1/binutils targets ran") depends on
# THESE, not on binutils-installed's/gcc-stage1-installed's own stamps.
# install-gcc/binutils' own "make install" only copies files that are
# actually newer, so these files' mtimes genuinely reflect "did a real
# rebuild happen" -- which a witness stamp touched unconditionally by
# an always-run recipe (see FORCE above) cannot. No recipe of their own
# on purpose: binutils-installed's/gcc-stage1-installed's recipes are
# what actually write these files; this just tells Make they exist and
# orders the dependency correctly.
$(CROSS_AS) $(CROSS_AR) $(CROSS_RANLIB): $(STAMP_DIR)/binutils-installed
$(CROSS_GCC): $(STAMP_DIR)/gcc-stage1-installed

# ---------------------------------------------------------------------
# Stage 1: binutils (as, ld, ar, ranlib, objdump, ... for $(TARGET))
# ---------------------------------------------------------------------
binutils: $(STAMP_DIR)/binutils-installed

$(STAMP_DIR)/binutils-installed: $(STAMP_DIR)/binutils-built | $(STAMP_DIR)
	cd $(BINUTILS_BUILD) && $(MAKE_J) install
	@touch $@

$(STAMP_DIR)/binutils-built: $(STAMP_DIR)/binutils-configured FORCE | $(STAMP_DIR)
	cd $(BINUTILS_BUILD) && $(MAKE_J)
	@touch $@

$(STAMP_DIR)/binutils-configured: | $(BINUTILS_BUILD) $(STAMP_DIR)
	cd $(BINUTILS_BUILD) && $(BINUTILS_SRC)/configure $(BINUTILS_CONFIGURE_FLAGS)
	@touch $@

# ---------------------------------------------------------------------
# Stage 2: GCC, first pass -- front-ends only (all-gcc), enough to
# produce a working $(TARGET)-gcc to build newlib with. No target libc
# assumed yet.
# ---------------------------------------------------------------------
gcc-stage1: $(STAMP_DIR)/gcc-stage1-installed

$(STAMP_DIR)/gcc-stage1-installed: $(STAMP_DIR)/gcc-stage1-built | $(STAMP_DIR)
	cd $(GCC_BUILD) && $(MAKE_J) install-gcc
	@touch $@

$(STAMP_DIR)/gcc-stage1-built: $(STAMP_DIR)/gcc-configured FORCE | $(STAMP_DIR)
	cd $(GCC_BUILD) && $(MAKE_J) all-gcc
	@touch $@

# binutils-installed is order-only here on purpose: gcc-configured must
# not run BEFORE binutils is installed, but must NOT be treated as out
# of date just because binutils-installed's own stamp was touched again
# (which now happens on every invocation, via FORCE above) -- configure
# output does not depend on a binutils REBUILD of the same source, only
# on binutils having been configured/built at all the first time
# (already covered by "the target doesn't exist yet"). A real
# (non-order-only) prerequisite here would make gcc-configured, and
# everything downstream of it, rerun on every single `make` invocation.
$(STAMP_DIR)/gcc-configured: | $(STAMP_DIR)/binutils-installed $(GCC_BUILD) $(STAMP_DIR)
	cd $(GCC_BUILD) && $(GCC_SRC)/configure $(GCC_CONFIGURE_FLAGS)
	@touch $@

# ---------------------------------------------------------------------
# Stage 3: newlib, ELF multilib (6809/6309/63f09/63f09hf), built and
# installed with the stage-1 cross-compiler. This is the C library
# GCC's own libgcc/libgfortran (stage 4, below) build against.
# ---------------------------------------------------------------------
newlib-elf: $(STAMP_DIR)/newlib-elf-installed

$(STAMP_DIR)/newlib-elf-installed: $(STAMP_DIR)/newlib-elf-built | $(STAMP_DIR)
	cd $(NEWLIB_ELF_BUILD) && $(MAKE_J) install
	@touch $@

# Real cross-tool files as prerequisites (not FORCE, and not the
# gcc-stage1-installed/binutils-installed witness stamps): newlib's own
# generated Makefile tracks only ITS OWN source files, with no notion at
# all of "the compiler used to build me changed" -- so Make itself must
# be the one to notice that here, from real, mtime-accurate file
# prerequisites (see the CROSS_GCC/CROSS_AR/CROSS_AS/CROSS_RANLIB rule
# above), and this recipe must force a full rebuild once triggered
# ("make clean" first) since newlib's own up-to-date object rules would
# otherwise see nothing to recompile against the new compiler. The
# "make clean" is a harmless no-op the very first time this runs
# (nothing built yet).
$(STAMP_DIR)/newlib-elf-built: $(STAMP_DIR)/newlib-elf-configured $(CROSS_GCC) $(CROSS_AR) $(CROSS_AS) $(CROSS_RANLIB) | $(STAMP_DIR)
	cd $(NEWLIB_ELF_BUILD) && $(MAKE_J) clean
	cd $(NEWLIB_ELF_BUILD) && $(MAKE_J)
	@touch $@

# gcc-stage1-installed order-only here, same reasoning as
# gcc-configured's own comment above: configure must run AFTER the
# cross-compiler is installed, but must not be treated as stale just
# because gcc-stage1-installed's stamp was touched again by an
# unrelated FORCE-driven rebuild attempt.
$(STAMP_DIR)/newlib-elf-configured: | $(STAMP_DIR)/gcc-stage1-installed $(NEWLIB_ELF_BUILD) $(STAMP_DIR)
	cd $(NEWLIB_ELF_BUILD) && $(NEWLIB_SRC)/configure $(NEWLIB_ELF_CONFIGURE_FLAGS)
	@touch $@

# ---------------------------------------------------------------------
# Stage 4: GCC, second pass -- now that newlib exists, this builds and
# installs the target libraries (libgcc, libgfortran, ...) across every
# multilib variant.
#
# "every multilib variant" is bigger than just the ELF one: t-m6809's
# MULTILIB_OPTIONS has a SECOND group orthogonal to the CPU submode one
# (mflex9/muniflex/msoc, pruned by MULTILIB_EXCEPTIONS down to exactly
# the six real combinations the newlib env variants below cover --
# flex9, 6309/flex9, uniflex, 6309/uniflex, 63f09/soc, 63f09hf/soc) --
# genmultilib's cartesian product means gcc-stage2 genuinely tries to
# configure and link-test libgcc/libgfortran for THOSE combinations too,
# not just the CPU-only ones ELF multilib covers. Real failure hit
# building this Makefile: gcc-stage2 ran before any newlib-<env> stamp
# below existed, so libgfortran's own sub-configure for e.g. "63f09/soc"
# found no real $(TARGET)/lib/63f09/soc/libc.a to link against yet --
# "checking whether symbol versioning is supported ... error: Link
# tests are not allowed after GCC_NO_EXECUTABLES", GCC's own signal
# that a target-library configure couldn't produce ANY working link.
# Depending on every newlib-<env> stamp too (not just newlib-elf's)
# closes this ordering gap.
# ---------------------------------------------------------------------
gcc-stage2: $(STAMP_DIR)/gcc-stage2-installed

$(STAMP_DIR)/gcc-stage2-installed: $(STAMP_DIR)/gcc-stage2-built | $(STAMP_DIR)
	cd $(GCC_BUILD) && $(MAKE_J) install
	@touch $@

# Real bug hit in practice: even after gcc-stage1 is FORCE-rebuilt above
# (see FORCE's own comment), a plain `make` in $(GCC_BUILD) leaves every
# libgcc/libgfortran/libquadmath .o file untouched -- confirmed directly
# (find ... -newer .../gcc/cc1 found 0 of 10640 .o files newer, right
# after a fresh cc1 rebuild). These target libraries are compiled BY the
# cross-compiler as an opaque external program; GCC's own Makefile
# machinery here tracks their SOURCE files, same blind spot as newlib's
# (see newlib-elf-built's own comment) -- so the same fix applies: real
# cross-tool files as prerequisites (CROSS_GCC in particular acts as a
# proxy for "did the m6809 backend's own source change", since
# gcc-stage1's FORCE-rebuilt all-gcc/install-gcc only touch CROSS_GCC's
# mtime when a real recompile happened), and a forced rebuild once
# triggered. Unlike newlib, a plain "make clean" here is wrong -- this
# is the SAME build tree as the host compiler (cc1 etc.), and a full
# clean would also wipe that, forcing an expensive, unnecessary
# multi-stage GCC rebuild just to refresh three target libraries. The
# scoped clean-target-libgcc/-libgfortran/-libquadmath targets (part of
# this GCC tree's own generated top Makefile, confirmed present) clean
# only the target libraries, leaving the host compiler alone.
$(STAMP_DIR)/gcc-stage2-built: $(STAMP_DIR)/newlib-elf-installed $(NEWLIB_ENV_NAMES:%=$(STAMP_DIR)/newlib-%-installed) $(CROSS_GCC) $(CROSS_AR) $(CROSS_AS) $(CROSS_RANLIB) | $(STAMP_DIR)
	cd $(GCC_BUILD) && $(MAKE_J) clean-target-libgcc clean-target-libgfortran clean-target-libquadmath
	cd $(GCC_BUILD) && $(MAKE_J)
	@touch $@

# libgfortran's own Makefile, unlike libgcc's, does not wire its
# multilib recursion into the ordinary "all"/"install" targets in this
# GCC version -- a real, documented asymmetry (see README.md), not
# something a plain `make`/`make install` in $(GCC_BUILD) ever picks
# up on its own. Re-running plain `./config.status` first recomputes
# MULTIDIRS and reconfigures the multilib subdirectories; without it,
# "make all-multi" can silently do nothing if libgfortran was
# configured before the cross-compiler reported multilib support.
libgfortran-multilib: $(STAMP_DIR)/libgfortran-multilib
$(STAMP_DIR)/libgfortran-multilib: $(STAMP_DIR)/gcc-stage2-installed | $(STAMP_DIR)
	cd $(LIBGFORTRAN_BUILD) && ./config.status
	cd $(LIBGFORTRAN_BUILD) && $(MAKE_J) all-multi
	cd $(LIBGFORTRAN_BUILD) && $(MAKE_J) install-multi
	@touch $@

# ---------------------------------------------------------------------
# Stage 5: newlib, one private (non-multilib) build per environment --
# FLEX9, FLEX9/6309, UniFLEX, UniFLEX/6309, SoC, SoC/FPU. Each only
# needs the stage-1 cross-compiler (not the ELF newlib or GCC's target
# libraries), so these can build any time after gcc-stage1.
#
# $(1)=name $(2)=--host $(3)=extra CFLAGS $(4)=dest subpath under lib/
define NEWLIB_ENV_RULES
NEWLIB_ENV_BUILD_$(1) := $$(NEWLIB_SRC)/build/$(1)
NEWLIB_ENV_INSTALL_$(1) := $$(NEWLIB_ENV_BUILD_$(1))/install

.PHONY: newlib-$(1)
newlib-$(1): $$(STAMP_DIR)/newlib-$(1)-installed

$$(STAMP_DIR)/newlib-$(1)-installed: $$(STAMP_DIR)/newlib-$(1)-built | $$(STAMP_DIR)
	cd $$(NEWLIB_ENV_BUILD_$(1)) && $$(MAKE_J) install
	mkdir -p $$(PREFIX_INSTALL)/$$(TARGET)/lib/$(4)
	cp -f $$(NEWLIB_ENV_INSTALL_$(1))/$(2)/lib/libc.a \
	      $$(NEWLIB_ENV_INSTALL_$(1))/$(2)/lib/libg.a \
	      $$(NEWLIB_ENV_INSTALL_$(1))/$(2)/lib/libm.a \
	      $$(PREFIX_INSTALL)/$$(TARGET)/lib/$(4)/
	@touch $$@

# Same real-file trigger + forced rebuild as newlib-elf-built above --
# this environment's own generated Makefile has the same blind spot to
# "the compiler changed" as the ELF one does.
$$(STAMP_DIR)/newlib-$(1)-built: $$(STAMP_DIR)/newlib-$(1)-configured $$(CROSS_GCC) $$(CROSS_AR) $$(CROSS_AS) $$(CROSS_RANLIB) | $$(STAMP_DIR)
	cd $$(NEWLIB_ENV_BUILD_$(1)) && $$(MAKE_J) clean
	cd $$(NEWLIB_ENV_BUILD_$(1)) && $$(MAKE_J)
	@touch $$@

# gcc-stage1-installed order-only, same reasoning as newlib-elf-
# configured's own comment above.
$$(STAMP_DIR)/newlib-$(1)-configured: | $$(STAMP_DIR)/gcc-stage1-installed $$(STAMP_DIR)
	mkdir -p $$(NEWLIB_ENV_BUILD_$(1))
	cd $$(NEWLIB_ENV_BUILD_$(1)) && $$(NEWLIB_SRC)/newlib/configure \
		--host=$(2) \
		CC=$$(CROSS_GCC) AR=$$(CROSS_AR) AS=$$(CROSS_AS) RANLIB=$$(CROSS_RANLIB) \
		CFLAGS='-g -O2 $(subst NONE,,$(3))' \
		--prefix=$$(NEWLIB_ENV_INSTALL_$(1))
	@touch $$@
endef

$(foreach s,$(NEWLIB_ENV_SPECS),$(eval $(call NEWLIB_ENV_RULES,$(word 1,$(subst |, ,$(s))),$(word 2,$(subst |, ,$(s))),$(word 3,$(subst |, ,$(s))),$(word 4,$(subst |, ,$(s))))))

newlib: newlib-elf $(NEWLIB_ENV_NAMES:%=newlib-%)

# ---------------------------------------------------------------------
clean:
	rm -rf $(BINUTILS_BUILD) $(GCC_BUILD) $(NEWLIB_ELF_BUILD) \
		$(NEWLIB_ENV_NAMES:%=$(NEWLIB_SRC)/build/%)

distclean: clean
	rm -rf $(STAMP_DIR)
