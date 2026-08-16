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

      # Any Firefox profile with a cookie store. Firefox on Linux keeps cookies
      # in plain sqlite, so browser-cookie3 reads them with no keyring involved,
      # and every invocation picks up the current ct0 -- which X rotates every
      # few hours -- instead of a value pasted once into a file.
      firefox_cookies=""
      for db in "$HOME"/.mozilla/firefox/*/cookies.sqlite; do
        [ -e "$db" ] || continue
        firefox_cookies="$db"
        break
      done

      if [ -n "''${TWITTER_AUTH_TOKEN:-}" ] && [ -n "''${TWITTER_CT0:-}" ]; then
        # Caller supplied a session explicitly; leave it alone.
        :
      elif [ -n "''${TWITTER_BROWSER:-}" ]; then
        # Caller picked the browser to read from; leave it alone.
        :
      elif [ -n "$firefox_cookies" ]; then
        export TWITTER_BROWSER=firefox
      elif [ -e "$cookies_file" ]; then
        if ! auth_token="$(jq -er '.auth_token' "$cookies_file" 2>/dev/null)" \
          || ! ct0="$(jq -er '.ct0' "$cookies_file" 2>/dev/null)"; then
          echo "twitter: no Firefox cookie store under ~/.mozilla/firefox, and" >&2
          echo "twitter: could not read auth_token and ct0 from $cookies_file" >&2
          echo 'twitter: expected {"auth_token": "...", "ct0": "..."}' >&2
          echo "twitter: template at secrets/x-cookies.example.json" >&2
          echo "twitter: simplest fix is to log in to x.com in Firefox instead --" >&2
          echo "twitter: its cookies are read live, so ct0 never goes stale" >&2
          exit 1
        fi
        export TWITTER_AUTH_TOKEN="$auth_token"
        export TWITTER_CT0="$ct0"
      else
        # Last resort: lift the session out of Brave. On Linux that means
        # decrypting Brave's cookie DB with a key from the system keyring
        # (libsecret/gnome-keyring), which is not guaranteed to be reachable
        # under Hyprland -- hence Firefox first.
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
