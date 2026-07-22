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

    # The driver's main keymap sends 0x13e (Fn+F4, whose keycap is the
    # microphone-mute key) as KEY_SUSPEND, which logind would act on. Remap it
    # to KEY_MICMUTE so the existing XF86AudioMicMute bind handles it and
    # nothing suspends the machine on a mic-mute press.
    services.udev.extraHwdb = ''
      evdev:name:Toshiba input device:dmi:*
       KEYBOARD_KEY_13e=micmute
    '';

    # Fn+F2 emits XF86Battery, bound to cycle power profiles. The X30W-K uses
    # intel_pstate EPP (no platform_profile), which ppd drives fine.
    services.power-profiles-daemon.enable = true;

    systemd.services.dynabook-hotkeys-enable = {
      description = "Load Dynabook hotkey SSDT, arm brightness flags, and set up keyboard backlight";
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
          # This is a "type 2" Toshiba keyboard backlight: the LED's on/off bit
          # is overridden by the SCI mode (auto=2/on=8/off=16), so real control
          # is the kbd_backlight_mode attribute. Default it to auto (lights on
          # keypress, off after the firmware timeout). The Fn+Z script cycles it
          # via passwordless sudo, since the driver recreates the attribute
          # root-owned on every mode change and it can't be made group-writable.
          mode=/sys/bus/acpi/devices/DNBK0001:00/kbd_backlight_mode
          if [ -e "$mode" ]; then
            echo 2 > "$mode" || true
          fi
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
