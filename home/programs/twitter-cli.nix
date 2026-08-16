{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  # X session cookies, read by absolute path at runtime. A plain string (not
  # builtins.path/readFile) keeps the secret out of the world-readable store and
  # lets evaluation succeed without the file present -- same convention as
  # modules/services/mihomo.nix. Git-ignored; see secrets/x-cookies.example.json.
  cookiesFile = "${osConfig.portable.configDir}/secrets/x-cookies.json";

  # Shadows the packaged `twitter` binary on PATH, so pkgs.twitter-cli itself is
  # deliberately not in home.packages (two bin/twitter would collide).
  twitter = pkgs.writeShellApplication {
    name = "twitter";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      cookies_file=${lib.escapeShellArg cookiesFile}

      if [ -n "''${TWITTER_AUTH_TOKEN:-}" ] && [ -n "''${TWITTER_CT0:-}" ]; then
        # Caller supplied a session explicitly; leave it alone.
        :
      elif [ -e "$cookies_file" ]; then
        if ! auth_token="$(jq -er '.auth_token' "$cookies_file" 2>/dev/null)" \
          || ! ct0="$(jq -er '.ct0' "$cookies_file" 2>/dev/null)"; then
          echo "twitter: could not read auth_token and ct0 from $cookies_file" >&2
          echo 'twitter: expected {"auth_token": "...", "ct0": "..."}' >&2
          echo "twitter: template at secrets/x-cookies.example.json" >&2
          echo "twitter: ct0 rotates every few hours -- refresh it from the browser" >&2
          exit 1
        fi
        export TWITTER_AUTH_TOKEN="$auth_token"
        export TWITTER_CT0="$ct0"
      else
        # Fallback: let browser-cookie3 lift the session out of Brave. On Linux
        # that means decrypting Brave's cookie DB with a key from the system
        # keyring (libsecret/gnome-keyring), which is not guaranteed to be
        # reachable under Hyprland. If it fails, write the cookies file instead.
        export TWITTER_BROWSER=brave
      fi

      exec ${pkgs.twitter-cli}/bin/twitter "$@"
    '';
  };
in
{
  # Read-only X client. `twitter bookmarks --json` / `--yaml` is the path to a
  # structured dump; nothing here writes to the account. Both roles.
  home.packages = [ twitter ];
}
