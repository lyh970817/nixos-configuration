{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Proxy secret, read by absolute path at activation/runtime as root. A plain
  # string (not builtins.path/readFile) keeps the secret out of the
  # world-readable store and lets evaluation succeed without the file present.
  # It lives in the config repo's git-ignored secrets/ dir (portable.configDir).
  mihomoConfig = "${config.portable.configDir}/secrets/mihomo-config.yaml";

  # Root-owned runtime state for the safe-apply / auto-revert mechanism.
  acceptedStateDir = "/var/lib/mihomo-config";
  lastGoodFile = "${acceptedStateDir}/last-good.yaml";
  pendingMarker = "${acceptedStateDir}/pending";
  # A rejected edit is preserved here before any revert overwrites the live
  # config, so an agent can inspect what it tried. May hold secrets: 0600 root.
  rejectedFile = "${acceptedStateDir}/rejected.yaml";

  # Timer payload: fired by the dead-man's-switch if a change is not confirmed
  # in time. Its own PATH must be complete because it runs under a minimal
  # transient-unit environment.
  revertHelper = pkgs.writeShellApplication {
    name = "mihomo-revert-helper";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      if [ -f ${lib.escapeShellArg mihomoConfig} ]; then
        cp -f -- ${lib.escapeShellArg mihomoConfig} ${lib.escapeShellArg rejectedFile}
        chmod 0600 ${lib.escapeShellArg rejectedFile}
      fi
      cp -f -- ${lib.escapeShellArg lastGoodFile} ${lib.escapeShellArg mihomoConfig}
      systemctl restart mihomo.service
      rm -f -- ${lib.escapeShellArg pendingMarker}
    '';
  };

  # Boot backstop: if we reboot while a change is still pending, the change was
  # never confirmed, so boot clean on the last-good config. Runs before mihomo
  # starts, so no restart is needed.
  bootCheck = pkgs.writeShellApplication {
    name = "mihomo-config-boot-check";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      [[ -e ${lib.escapeShellArg pendingMarker} ]] || exit 0
      if [[ -e ${lib.escapeShellArg lastGoodFile} ]]; then
        if [ -f ${lib.escapeShellArg mihomoConfig} ]; then
          cp -f -- ${lib.escapeShellArg mihomoConfig} ${lib.escapeShellArg rejectedFile}
          chmod 0600 ${lib.escapeShellArg rejectedFile}
        fi
        cp -f -- ${lib.escapeShellArg lastGoodFile} ${lib.escapeShellArg mihomoConfig}
      fi
      rm -f -- ${lib.escapeShellArg pendingMarker}
    '';
  };

  mihomoGuard = pkgs.writeShellApplication {
    name = "mihomo-guard";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      readonly STATE_DIR=${lib.escapeShellArg acceptedStateDir}
      readonly LAST_GOOD=${lib.escapeShellArg lastGoodFile}
      readonly PENDING=${lib.escapeShellArg pendingMarker}
      readonly LIVE_CONFIG=${lib.escapeShellArg mihomoConfig}
      readonly REJECTED=${lib.escapeShellArg rejectedFile}

      die() {
        printf 'mihomo-guard: %s\n' "$*" >&2
        exit 1
      }

      require_root() {
        (( EUID == 0 )) || die "must be run as root: use sudo"
      }

      config_sha() {
        sha256sum -- "$1" | cut -d ' ' -f 1
      }

      disarm() {
        systemctl stop mihomo-revert.timer 2>/dev/null || true
        systemctl stop mihomo-revert.service 2>/dev/null || true
        systemctl reset-failed mihomo-revert.timer mihomo-revert.service 2>/dev/null || true
      }

      try() {
        local timeout="''${1:-90}"

        require_root
        [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -gt 0 ]] ||
          die "timeout must be a positive integer number of seconds"
        [[ -e "$LAST_GOOD" ]] ||
          die "no baseline yet — run 'sudo mihomo-guard keep' once while your connection works"
        [[ ! -e "$PENDING" ]] ||
          die "a change is already pending; run 'mihomo-guard keep' or 'mihomo-guard revert' first"

        disarm

        install -d -m 0755 -o root -g root "$STATE_DIR"
        : >"$PENDING"

        # Arm the dead-man's switch BEFORE restarting mihomo, so a broken
        # config that severs connectivity still auto-reverts.
        systemd-run --unit=mihomo-revert --on-active="''${timeout}s" \
          --timer-property=AccuracySec=1s --collect \
          ${revertHelper}/bin/mihomo-revert-helper

        systemctl restart mihomo.service

        printf 'Armed auto-revert for %s seconds (TUN restart briefly blips all traffic).\n' "$timeout"
        printf 'Verify connectivity, then run:\n'
        printf '  sudo mihomo-guard keep     # confirm and make this the new baseline\n'
        printf '  sudo mihomo-guard revert   # undo now and restore last-good\n'
        printf 'If neither runs in time, the last-good config is restored automatically.\n'
      }

      keep() {
        require_root
        disarm

        [[ -e "$LIVE_CONFIG" ]] || die "live config not found: $LIVE_CONFIG"
        [[ ! -L "$STATE_DIR" ]] || die "state directory must not be a symlink"
        install -d -m 0755 -o root -g root "$STATE_DIR"

        local temporary
        temporary=$(mktemp "$STATE_DIR/.last-good.yaml.XXXXXX")
        trap 'rm -f -- "$temporary"' EXIT
        cp -f -- "$LIVE_CONFIG" "$temporary"
        chown root:root "$temporary"
        chmod 0600 "$temporary"
        mv -fT -- "$temporary" "$LAST_GOOD"
        trap - EXIT

        rm -f -- "$PENDING"
        printf 'Baseline updated: current live config recorded as last-good.\n'
      }

      revert() {
        require_root
        [[ -e "$LAST_GOOD" ]] || die "no baseline to revert to: $LAST_GOOD"
        disarm

        # Preserve the rejected edit so an agent can inspect what it tried.
        if [ -f "$LIVE_CONFIG" ]; then
          cp -f -- "$LIVE_CONFIG" "$REJECTED"
          chmod 0600 "$REJECTED"
        fi

        # cp -f preserves the live config's own ownership/mode (0600
        # andongni:users); do not chown it.
        cp -f -- "$LAST_GOOD" "$LIVE_CONFIG"
        systemctl restart mihomo.service

        rm -f -- "$PENDING"
        printf 'Reverted to last-good config (rejected edit saved to %s) and restarted mihomo.\n' "$REJECTED"
      }

      status() {
        if [[ -e "$LAST_GOOD" ]]; then
          printf 'last-good.yaml: present\n'
          if [[ -e "$LIVE_CONFIG" ]]; then
            if [[ "$(config_sha "$LIVE_CONFIG")" == "$(config_sha "$LAST_GOOD")" ]]; then
              printf 'live config:    matches last-good\n'
            else
              printf 'live config:    differs from last-good\n'
            fi
          else
            printf 'live config:    missing (%s)\n' "$LIVE_CONFIG"
          fi
        else
          printf 'last-good.yaml: absent (run: sudo mihomo-guard keep)\n'
        fi

        if [[ -e "$PENDING" ]]; then
          printf 'pending change: yes\n'
        else
          printf 'pending change: no\n'
        fi

        if systemctl is-active --quiet mihomo-revert.timer; then
          printf 'revert timer:   active\n'
        else
          printf 'revert timer:   inactive\n'
        fi
      }

      case "''${1:-}" in
        try)
          shift
          try "$@"
          ;;
        keep)
          [[ $# -eq 1 ]] || die "usage: sudo mihomo-guard keep"
          keep
          ;;
        revert)
          [[ $# -eq 1 ]] || die "usage: sudo mihomo-guard revert"
          revert
          ;;
        status)
          [[ $# -eq 1 ]] || die "usage: mihomo-guard status"
          status
          ;;
        *)
          die "usage: mihomo-guard {try [timeout]|keep|revert|status}"
          ;;
      esac
    '';
  };
in
{
  # Mihomo (Clash Meta) proxy service
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = mihomoConfig;
  };

  environment.systemPackages = [ mihomoGuard ];

  # Let the active local wheel session start/stop just this unit without a
  # password prompt, so the laptop's Fn+F8 key (bound to a mihomo toggle in
  # Hyprland) works from the session. Scoped to mihomo.service and the
  # start/stop/restart verbs; every other unit still needs normal auth.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "mihomo.service" &&
          subject.active && subject.isInGroup("wheel")) {
        var verb = action.lookup("verb");
        if (verb == "start" || verb == "stop" || verb == "restart") {
          return polkit.Result.YES;
        }
      }
    });
  '';

  # Ensure the root-owned state dir exists for the guard/boot-check tools.
  systemd.tmpfiles.rules = [
    "d ${acceptedStateDir} 0755 root root -"
  ];

  # Reboot-during-pending backstop: restore last-good before mihomo starts.
  systemd.services.mihomo-config-boot-check = {
    description = "Restore last-good mihomo config if a change was left pending across reboot";
    before = [ "mihomo.service" ];
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    # The live config may sit under a non-local mount (e.g. the Yandex.Disk
    # home path); wait for it before reading/writing there.
    unitConfig.RequiresMountsFor = builtins.dirOf mihomoConfig;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bootCheck}/bin/mihomo-config-boot-check";
    };
  };
}
