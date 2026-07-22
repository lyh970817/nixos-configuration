{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:

# Out-of-tree build of the in-tree toshiba_acpi driver with two small patches:
# (1) add the Dynabook Portege X30W-K's ACPI HID (DNBK0001) to the match table
# (below, via substituteInPlace), and (2) drain the INFO() hotkey FIFO fully on
# each notify instead of popping one entry (toshiba-acpi-dnbk-drain.patch) — this
# firmware pushes several FIFO entries per Fn combo and a dropped/coalesced
# notify would otherwise desync later key presses. The \_SB.VALZ device (_HID
# DNBK0001) implements the exact mainline HCI/SCI GHCI protocol and an INFO()
# hotkey FIFO, but mainline matches only the older TOS6200/6207/6208/1900 HIDs,
# so the stock module never binds here.
#
# The source is taken verbatim from the running kernel's own tarball (no new
# fetch/hash), so it always matches the running ABI. The module is renamed to
# `toshiba_acpi_dnbk` so its .ko never collides with the in-tree
# toshiba_acpi.ko at depmod time. On this machine the in-tree module is never
# even loaded (no TOS* device is present — only DNBK*/TOS620D, none of which the
# stock table matches), so the shared internal acpi_driver name cannot clash;
# renaming the file is purely belt-and-suspenders against a future manual
# `modprobe toshiba_acpi`.
stdenv.mkDerivation {
  pname = "toshiba-acpi-dnbk";
  version = kernel.version;

  inherit (kernel) src;

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # Only the single driver file is needed; unpack it alone from the (large)
  # kernel tarball rather than the whole tree.
  unpackPhase = ''
    runHook preUnpack
    tar -xf "$src" --wildcards --strip-components=4 \
      '*/drivers/platform/x86/toshiba_acpi.c'
    runHook postUnpack
  '';
  sourceRoot = ".";

  # Applied in patchPhase, before the DNBK substitution/rename in postPatch.
  patches = [ ./toshiba-acpi-dnbk-drain.patch ];

  postPatch = ''
    # Add the X30W-K HID next to the existing Toshiba HIDs in the match table.
    substituteInPlace toshiba_acpi.c \
      --replace-fail $'\t{"TOS1900", 0},' $'\t{"TOS1900", 0},\n\t{"DNBK0001", 0},'

    # Rename so the resulting module is toshiba_acpi_dnbk.ko.
    mv toshiba_acpi.c toshiba_acpi_dnbk.c

    # Kbuild wrapper; the recipe line must be tab-indented, hence printf.
    {
      printf 'obj-m := toshiba_acpi_dnbk.o\n'
      printf 'KDIR ?= /lib/modules/$(shell uname -r)/build\n'
      printf 'all:\n'
      printf '\t$(MAKE) -C $(KDIR) M=$(CURDIR) modules\n'
    } > Makefile
  '';

  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    install -D toshiba_acpi_dnbk.ko \
      "$out/lib/modules/${kernel.modDirVersion}/misc/toshiba_acpi_dnbk.ko"
    runHook postInstall
  '';

  meta = {
    description = "toshiba_acpi kernel module patched to bind the Dynabook Portege X30W-K (DNBK0001)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
