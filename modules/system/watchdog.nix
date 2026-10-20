{ config, lib, ... }:
{
  # Self-recovery for the unattended home desktop. Neither helps against a
  # memory thrash (PID 1 keeps petting the watchdog while everything else
  # crawls); modules/system/earlyoom.nix is the defence for that. These cover
  # the hard cases: a kernel panic otherwise sits on the panic screen until
  # someone is physically there, and a hung kernel or PID 1 never recovers.
  boot.kernelParams = [ "panic=10" ];

  # linglong's chipset exposes an SP5100 TCO timer (`wdctl`, 60 s max). systemd
  # arms it and resets the machine when it stops petting it; the default 10 min
  # reboot watchdog already guards a shutdown that wedges.
  systemd.watchdog.runtimeTime = lib.mkIf (config.portable.role == "home") "30s";
}
