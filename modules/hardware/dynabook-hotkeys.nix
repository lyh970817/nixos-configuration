{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Dynabook X30W-K only; the SSDT targets ACPI objects (\SYSE/\VALF/\HPEN,
  # \_SB.VALZ) specific to this machine's firmware.
  ssdtAml = pkgs.runCommand "ssdt-dynahk.aml" { nativeBuildInputs = [ pkgs.acpica-tools ]; } ''
    iasl -oa -p out ${./dynabook-hotkeys.dsl}
    cp out.aml $out
  '';

  # toshiba_acpi patched to bind this machine's \_SB.VALZ (_HID DNBK0001),
  # giving us the Fn hotkey FIFO (INFO()), keyboard-backlight LED, and rfkill.
  # Built against the running kernel via kernelPackages.callPackage so it picks
  # up `kernel` and `kernelModuleMakeFlags` from that scope.
  toshibaAcpiDnbk = config.boot.kernelPackages.callPackage ../../pkgs/toshiba-acpi-dnbk.nix { };

  hpstEnable = pkgs.writeShellScript "dynabook-hpst-enable" ''
    set -eu
    printf '\\_SB.DYHK.HPST' > /proc/acpi/call
    # The reply carries a trailing NUL; strip it to avoid bash warnings.
    reply="$(tr -d '\0' < /proc/acpi/call)"
    case "$reply" in
      0x1*) ;;
      *) echo "dynabook-hpst-enable: unexpected /proc/acpi/call reply: $reply" >&2; exit 1 ;;
    esac
  '';
in
{
  # Fn+F6/F7 brightness keys: the EC only emits ACPI video brightness notifies
  # once firmware mailbox flags SYSE/VALF/HPEN are set. Windows vendor tools
  # set them; on Linux we load a custom SSDT defining \_SB.DYHK.HPST and call
  # it once via acpi_call, since hot-loaded tables don't run _INI. Opt-in per
  # machine via portable.quirks.dynabookX30wkHotkeys in local.nix.
  config = lib.mkIf config.portable.quirks.dynabookX30wkHotkeys {
    boot.extraModulePackages = [
      config.boot.kernelPackages.acpi_call
      toshibaAcpiDnbk
    ];
    boot.kernelModules = [
      "acpi_call"
      "acpi_configfs"
      # Patched toshiba_acpi that matches DNBK0001; provides the Fn hotkey input
      # device, kbd_backlight LED, and rfkill. Note: this reports
      # KEY_BRIGHTNESSUP/DOWN for Fn+F6/F7 in addition to the Video Bus notifies
      # the SSDT/HPEN path already enables, so brightness may double-step until
      # one path is suppressed (known follow-up; HPEN kept for now).
      "toshiba_acpi_dnbk"
    ];

    systemd.services.dynabook-hotkeys-enable = {
      description = "Load Dynabook hotkey SSDT and enable Fn+F6/F7 brightness mailbox flags";
      after = [
        "systemd-modules-load.service"
        "sys-kernel-config.mount"
      ];
      requires = [ "sys-kernel-config.mount" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExists = "/proc/acpi/call";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "dynabook-hotkeys-enable" ''
          set -eu
          tbl=/sys/kernel/config/acpi/table/dynahk
          if [ ! -d "$tbl" ]; then
            mkdir "$tbl"
            cat ${ssdtAml} > "$tbl/aml"
          fi
          ${hpstEnable}
        '';
      };
    };

    # The firmware may clear the mailbox flags across suspend/resume; re-arm
    # them without blocking resume if the SSDT/acpi_call path is unavailable.
    powerManagement.resumeCommands = ''
      ${hpstEnable} || true
    '';
  };
}
