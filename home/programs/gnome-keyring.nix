{
  lib,
  pkgs,
  ...
}:

{
  # User-side half of modules/services/gnome-keyring.nix. That module enables
  # the Secret Service daemon and pam_gnome_keyring; this one makes sure the
  # login keyring actually exists so nothing ever prompts for a passphrase.
  #
  # Autologin (services/greetd.nix) hands PAM no password, so pam_gnome_keyring
  # starts the daemon but cannot create the login keyring. Without the file the
  # first consumer (Claude Desktop, Brave/Chromium Safe Storage, Bitwarden) only
  # finds the volatile `session` collection and gcr pops its "choose a password
  # for the new keyring" prompt.
  #
  # An empty passphrase means gnome-keyring keeps the keyring in its plaintext
  # textual format, which the daemon unlocks transparently on first use. The
  # tradeoff is the one already accepted in the system module: login.keyring is
  # cleartext on an unencrypted root, where autologin has put the security
  # boundary at physical access anyway.
  #
  # Seeding only ever fills in what is missing: an existing keyring (including
  # one the user gave a real passphrase) is left completely untouched.
  home.activation.loginKeyring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    keyring_dir="$HOME/.local/share/keyrings"
    login_keyring="$keyring_dir/login.keyring"
    default_keyring="$keyring_dir/default"

    run ${pkgs.coreutils}/bin/install -d -m 0700 "$keyring_dir"

    if [ ! -e "$login_keyring" ]; then
      keyring_tmp="$(${pkgs.coreutils}/bin/mktemp "$keyring_dir/login.keyring.XXXXXX")"
      {
        echo "[keyring]"
        echo "display-name=login"
        echo "ctime=$(${pkgs.coreutils}/bin/date +%s)"
        echo "mtime=0"
        echo "lock-on-idle=false"
        echo "lock-after=false"
      } > "$keyring_tmp"
      run ${pkgs.coreutils}/bin/chmod 0600 "$keyring_tmp"
      run ${pkgs.coreutils}/bin/mv -f "$keyring_tmp" "$login_keyring"
    fi

    # Alias resolution for the `default` collection libsecret asks for. Written
    # without a trailing newline, the way gnome-keyring writes it itself.
    if [ ! -e "$default_keyring" ]; then
      default_tmp="$(${pkgs.coreutils}/bin/mktemp "$keyring_dir/default.XXXXXX")"
      ${pkgs.coreutils}/bin/printf login > "$default_tmp"
      run ${pkgs.coreutils}/bin/chmod 0644 "$default_tmp"
      run ${pkgs.coreutils}/bin/mv -f "$default_tmp" "$default_keyring"
    fi
  '';
}
