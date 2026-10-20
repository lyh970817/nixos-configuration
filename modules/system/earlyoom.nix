{
  # Kill the memory hog before the machine thrashes itself unreachable.
  #
  # Without this there is no userspace OOM killer at all: systemd-oomd runs
  # but, with every `systemd.oomd.enable*Slice` option off, monitors zero
  # cgroups (`oomctl dump`). The kernel OOM killer only fires once RAM *and*
  # the whole swap partition are exhausted, and the swap is as large as RAM,
  # so the machine first pages for hours at a crawl -- on linglong, from the
  # first "Under memory pressure" at 06:04 to the kernel kill at 10:44, then
  # nine more hours unusable: tailscaled could not even start within its 90 s
  # timeout, so the node went "offline" and SSH was gone. When the kernel did
  # kill, it chose a 2.8 MB ChatGPT renderer: Chromium renderers carry
  # oom_score_adj 300, which the kernel's badness counts as 30 % of all
  # memory, so they always outrank the real 7 GB hog, and killing them frees
  # nothing.
  #
  # earlyoom acts on free RAM and free swap together, SIGTERMs one process,
  # and with --sort-by-rss picks the largest resident process instead of the
  # oom_score the renderers distort. Both thresholds must be crossed: memory
  # low *and* more than half the swap in use is the point at which paging has
  # begun eating working sets, well before the kernel would act.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 8; # SIGTERM below 8 % available RAM, SIGKILL below 4 %
    freeSwapThreshold = 50; # ... and only once over half the swap is in use
    # Desktop notification through systembus-notify so a kill is noticed.
    enableNotifications = true;
    extraArgs = [
      "--sort-by-rss"
      # Keep the remote-access path and the session alive if at all possible;
      # --avoid only lowers their badness, it does not exempt them.
      "--avoid"
      "^(tailscaled|mihomo|sshd|mosh-server|Hyprland|tmux: server|keyd|greetd|systemd.*|dbus.*|pipewire|wireplumber)$"
    ];
  };
}
