{ pkgs, ... }:

let
  # A bluray ISO is a UDF image with a BDMV directory at its root; anything
  # else has no playlist for mpv's bd:// loader. Plays locally on the machine
  # Yazi runs on -- deliberately no mosh/peer dispatch like image-open.nix.
  openIso = pkgs.writeShellApplication {
    name = "yazi-open-iso";
    runtimeInputs = [
      pkgs.p7zip
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      # Capture the listing rather than piping straight into `grep -q`: with
      # pipefail, grep's early exit can SIGPIPE 7z and fail the pipeline even
      # when BDMV was found.
      listing="$(7z l -- "$1" 2>/dev/null || true)"

      if grep -q BDMV <<< "$listing"; then
        # mpv comes from PATH at runtime (home/programs/mpv.nix), so it stays
        # the configured player rather than a second pinned copy.
        exec mpv --force-window bd:// --bluray-device="$1"
      fi

      notify-send "yazi-open-iso" "Not a bluray ISO: $(basename "$1")"
      exit 0
    '';
  };
in
{
  home.packages = [ openIso ];
}
