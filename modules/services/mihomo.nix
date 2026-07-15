{
  config,
  pkgs,
  lib,
  ...
}:

let
  mihomoConfig = /. + "/home/andongni/Yandex.Disk/System/nixos-configuration/mihomo-config.yaml";
  acceptedStateDir = "/var/lib/mihomo-config";
  acceptedShaFile = "${acceptedStateDir}/accepted-config.sha256";

  mihomoConfigCli = pkgs.writeShellApplication {
    name = "mihomo-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.systemd
    ];
    text = ''
      readonly UNIT_FILE="/run/current-system/etc/systemd/system/mihomo.service"
      readonly SYSTEM_PROFILE="/nix/var/nix/profiles/system"
      readonly STATE_DIR="${acceptedStateDir}"
      readonly ACCEPTED_SHA_FILE="${acceptedShaFile}"

      die() {
        printf 'mihomo-config: %s\n' "$*" >&2
        exit 1
      }

      active_config_path() {
        local candidate
        local canonical
        local -a config_paths=()

        [[ -f "$UNIT_FILE" && ! -L "$UNIT_FILE" ]] ||
          die "active Mihomo service unit is unavailable: $UNIT_FILE"

        while IFS= read -r candidate; do
          config_paths+=("$candidate")
        done < <(sed -n 's|^LoadCredential=config\.yaml:\(/nix/store/[^[:space:]]\+\)$|\1|p' "$UNIT_FILE")

        (( ''${#config_paths[@]} == 1 )) ||
          die "expected exactly one config.yaml LoadCredential in the active Mihomo service unit"

        candidate="''${config_paths[0]}"
        [[ "$candidate" == /nix/store/* ]] ||
          die "active Mihomo configuration is outside /nix/store"
        [[ -f "$candidate" && ! -L "$candidate" ]] ||
          die "active Mihomo configuration is not a regular store file"
        canonical=$(realpath -e -- "$candidate") ||
          die "cannot resolve the active Mihomo configuration"
        [[ "$canonical" == "$candidate" ]] ||
          die "active Mihomo configuration must be a canonical store path"

        printf '%s\n' "$candidate"
      }

      config_sha() {
        sha256sum -- "$1" | sed 's/[[:space:]].*$//'
      }

      read_accepted_sha() {
        local accepted

        [[ -e "$ACCEPTED_SHA_FILE" ]] || return 1
        [[ -f "$ACCEPTED_SHA_FILE" && ! -L "$ACCEPTED_SHA_FILE" ]] ||
          die "accepted configuration state is not a regular file"
        accepted=$(sed -n '1p' "$ACCEPTED_SHA_FILE")
        [[ "$accepted" =~ ^[0-9a-f]{64}$ ]] ||
          die "accepted configuration state is invalid"
        [[ $(sed -n '2p' "$ACCEPTED_SHA_FILE") == "" ]] ||
          die "accepted configuration state is invalid"
        printf '%s\n' "$accepted"
      }

      status() {
        local active_path
        local active_sha
        local accepted_sha

        active_path=$(active_config_path)
        active_sha=$(config_sha "$active_path")

        printf 'Active Mihomo config: %s\n' "$active_path"
        printf 'Active SHA-256:      %s\n' "$active_sha"
        if accepted_sha=$(read_accepted_sha); then
          printf 'Accepted SHA-256:    %s\n' "$accepted_sha"
          if [[ "$active_sha" == "$accepted_sha" ]]; then
            printf 'Status:              accepted\n'
          else
            printf 'Status:              not accepted\n'
          fi
        else
          printf 'Accepted SHA-256:    none\n'
          printf 'Status:              not accepted\n'
        fi
      }

      accept() {
        local active_before
        local active_after
        local profile_before
        local profile_after
        local active_path
        local active_sha
        local temporary

        (( EUID == 0 )) || die "accept must be run with sudo"

        active_before=$(readlink -f /run/current-system) ||
          die "cannot resolve the active system closure"
        profile_before=$(readlink -f "$SYSTEM_PROFILE") ||
          die "cannot resolve the persistent system profile"
        [[ "$active_before" == /nix/store/* && "$active_before" == "$profile_before" ]] ||
          die "active system does not match the persistent system profile"
        systemctl is-active --quiet mihomo.service ||
          die "mihomo.service is not active"

        active_path=$(active_config_path)
        active_sha=$(config_sha "$active_path")

        active_after=$(readlink -f /run/current-system) ||
          die "cannot recheck the active system closure"
        profile_after=$(readlink -f "$SYSTEM_PROFILE") ||
          die "cannot recheck the persistent system profile"
        [[ "$active_after" == "$active_before" && "$profile_after" == "$profile_before" ]] ||
          die "system generation changed while accepting the Mihomo configuration"
        systemctl is-active --quiet mihomo.service ||
          die "mihomo.service stopped while accepting its configuration"

        [[ ! -L "$STATE_DIR" ]] || die "state directory must not be a symlink"
        install -d -m 0755 -o root -g root "$STATE_DIR"
        temporary=$(mktemp "$STATE_DIR/.accepted-config.sha256.XXXXXX")
        trap 'rm -f -- "$temporary"' EXIT
        printf '%s\n' "$active_sha" >"$temporary"
        chown root:root "$temporary"
        chmod 0644 "$temporary"
        mv -fT -- "$temporary" "$ACCEPTED_SHA_FILE"
        trap - EXIT

        printf 'Accepted the active Mihomo configuration.\n'
        printf 'SHA-256: %s\n' "$active_sha"
      }

      case "''${1:-}" in
        status)
          [[ $# -eq 1 ]] || die "usage: mihomo-config status"
          status
          ;;
        accept)
          [[ $# -eq 1 ]] || die "usage: sudo mihomo-config accept"
          accept
          ;;
        *)
          die "usage: mihomo-config {status|accept}"
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

  environment.systemPackages = [ mihomoConfigCli ];

  system.activationScripts.mihomoConfigAcceptance = lib.stringAfter [ "etc" ] ''
        candidate_sha="$(${pkgs.coreutils}/bin/sha256sum -- ${lib.escapeShellArg (toString mihomoConfig)} | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)"
        accepted_sha=""
        if [ -f ${lib.escapeShellArg acceptedShaFile} ] && [ ! -L ${lib.escapeShellArg acceptedShaFile} ]; then
          accepted_sha="$(${pkgs.coreutils}/bin/head -n 1 -- ${lib.escapeShellArg acceptedShaFile})"
        fi

        if [ "$candidate_sha" != "$accepted_sha" ]; then
          ${pkgs.coreutils}/bin/cat <<'EOF'

    Mihomo configuration has changed and has not been accepted yet.
    Test your connection and routing now. If everything works, run:

      sudo mihomo-config accept

    Until it is accepted, this reminder will appear after each rebuild.
    EOF
        fi
  '';
}
