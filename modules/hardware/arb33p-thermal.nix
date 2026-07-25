{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Thermal envelope tuning knobs for ryzenadj (ARB33P board, Ryzen 7 8840U,
  # amd-pstate-epp). tctlTemp is the Tctl throttle target in degrees C;
  # stapmLimit/slowLimit are the sustained (STAPM/slow) power limits in mW,
  # fastLimit is the short-burst ceiling in mW that lets boost reach higher
  # clocks briefly before settling back to the sustained limits.
  tctlTemp = "80";
  stapmLimit = "18000";
  slowLimit = "18000";
  fastLimit = "30000";
in
{
  # ARB33P (Ryzen 7 8840U) thermal/power management. The board previously ran
  # unmanaged up to the 105/110C ACPI trip points (observed sitting at ~95C
  # Tctl under load); boost is left enabled for bursts, and ryzenadj caps
  # sustained power/thermals so heavy remote-compute jobs settle at tctlTemp
  # instead. Opt-in per machine via portable.quirks.arb33pThermalCap in
  # local.nix.
  config = lib.mkIf config.portable.quirks.arb33pThermalCap {
    services.power-profiles-daemon.enable = true;

    # ryzen_smu gives ryzenadj access to the SMU without needing to relax
    # /dev/mem access via iomem=relaxed (which would require a reboot to take
    # effect). Built against the running kernel via kernelPackages so it stays
    # in sync across kernel upgrades.
    boot.extraModulePackages = [ config.boot.kernelPackages.ryzen-smu ];
    boot.kernelModules = [ "ryzen_smu" ];

    environment.systemPackages = [ pkgs.ryzenadj ];

    systemd.services.ryzenadj = {
      description = "Apply ryzenadj thermal/power envelope";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.ryzenadj}/bin/ryzenadj --tctl-temp=${tctlTemp} --stapm-limit=${stapmLimit} --slow-limit=${slowLimit} --fast-limit=${fastLimit}";
      };
    };

    # The SMU can reset/clear the limits after ACPI events (e.g.
    # suspend/resume, AC/battery transitions), so reapply periodically rather
    # than only at boot.
    systemd.timers.ryzenadj = {
      description = "Periodically reapply ryzenadj thermal/power envelope";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "60s";
        Unit = "ryzenadj.service";
      };
    };
  };
}
