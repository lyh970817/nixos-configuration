{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Dynabook X30W-K only; the SSDT targets ACPI objects (\SYSE/\VALF,
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

  # Pick the power profile from the AC/Mains state: plugged in -> balanced, on
  # battery -> power-saver. Matched on the supply type (not the ADP1 name) so it
  # is firmware-name-agnostic. Called both from the boot oneshot and the udev
  # rule; tolerant of power-profiles-daemon not being up yet (a udev coldplug
  # can fire before ppd starts — the oneshot re-applies once it is running).
  powerProfileAuto = pkgs.writeShellScript "dynabook-power-profile-auto" ''
    set -eu
    prof=power-saver
    for ps in /sys/class/power_supply/*; do
      [ -r "$ps/type" ] || continue
      if [ "$(cat "$ps/type")" = "Mains" ]; then
        if [ "$(cat "$ps/online" 2> /dev/null || echo 0)" = "1" ]; then
          prof=balanced
        fi
        break
      fi
    done
    ${pkgs.coreutils}/bin/timeout 5 ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$prof" 2> /dev/null || true
  '';
in
{
  # Fn+F6/F7 brightness keys: the EC only pushes the hotkey codes into the VALZ
  # INFO() FIFO once firmware mailbox flags SYSE/VALF are set. Windows vendor
  # tools set them; on Linux we load a custom SSDT defining \_SB.DYHK.HPST and
  # call it once via acpi_call, since hot-loaded tables don't run _INI. The
  # toshiba_acpi_dnbk driver then turns those FIFO codes into KEY_BRIGHTNESS*
  # events. Opt-in per machine via portable.quirks.dynabookX30wkHotkeys in
  # local.nix.
  config = lib.mkIf config.portable.quirks.dynabookX30wkHotkeys {
    boot.extraModulePackages = [
      config.boot.kernelPackages.acpi_call
      toshibaAcpiDnbk
    ];
    boot.kernelModules = [
      "acpi_call"
      "acpi_configfs"
      # Patched toshiba_acpi that matches DNBK0001; provides the Fn hotkey input
      # device, kbd_backlight LED, and rfkill. Fn+F6/F7 brightness now flows
      # solely through this driver's keymap (KEY_BRIGHTNESSDOWN/UP); the SSDT no
      # longer sets HPEN, so the firmware's duplicate acpi_video notifies are
      # suppressed and brightness steps once per press.
      "toshiba_acpi_dnbk"
    ];

    # Remaps for the Toshiba hotkey device:
    # - 0x13e (Fn+F4, mic-mute keycap) is KEY_SUSPEND in the driver keymap,
    #   which logind would act on; remap to KEY_MICMUTE so the existing
    #   XF86AudioMicMute bind handles it and nothing suspends on a mic press.
    # - 0x139 (Fn+Space) is KEY_ZOOMRESET (420), but keyd's virtual keyboard
    #   (it grabs all keyboards) does not declare code 420, so it silently drops
    #   the event on re-emit and Hyprland never sees it. Remap to KEY_F21 (191),
    #   an ordinary sub-256 code keyd forwards, and bind that in Hyprland.
    services.udev.extraHwdb = ''
      evdev:name:Toshiba input device:dmi:*
       KEYBOARD_KEY_13e=micmute
       KEYBOARD_KEY_139=f21
    '';

    # Fn+F2 emits XF86Battery, bound to cycle power profiles. The X30W-K uses
    # intel_pstate EPP (no platform_profile), which ppd drives fine.
    services.power-profiles-daemon.enable = true;

    # Automatic profile by power source: plug -> balanced, unplug -> power-saver,
    # applied on every Mains online change and once at boot. A manual Fn+F2
    # choice therefore persists until the next plug/unplug, when the automatic
    # default reasserts (intended). Inert on any host without a Mains supply.
    services.udev.extraRules = ''
      ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${powerProfileAuto}"
    '';

    systemd.services.dynabook-power-profile-init = {
      description = "Apply the AC/battery power profile for the current power source at boot";
      # ppd must be up to accept the profile; the oneshot also covers the boot
      # case the udev coldplug can miss (fired before ppd was running).
      after = [ "power-profiles-daemon.service" ];
      wants = [ "power-profiles-daemon.service" ];
      # ppd itself is ordered After=multi-user.target, so hanging this oneshot
      # off multi-user.target creates an ordering cycle and systemd deletes the
      # job at every boot (the profile was never applied). graphical.target is
      # reached after ppd, so the ordering is consistent there.
      wantedBy = [ "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = powerProfileAuto;
      };
    };

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
