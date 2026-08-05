{ ... }:

{
  # Secret Service provider (org.freedesktop.secrets). Electron and Chromium
  # apps reach it through libsecret to persist logins: Claude Desktop refuses
  # to save its sign-in without one, and Brave/Chromium/Bitwarden all store
  # their Safe Storage key here. Not tied to a single app — do not drop this
  # as orphaned again just because one consumer goes away.
  #
  # greetd logs in without a password (services/greetd.nix runs the session
  # directly as the user), so pam_gnome_keyring has no passphrase to unlock
  # with and creates the login keyring with an empty one. That keyring
  # auto-unlocks with no prompt, which is what makes this work headlessly
  # under Hyprland, but it also leaves ~/.local/share/keyrings/login.keyring
  # readable as cleartext. The root filesystem is unencrypted, so autologin
  # already sets the real security boundary at physical access.
  services.gnome.gnome-keyring.enable = true;

  # nixpkgs defaults this to gnome-keyring's own enable flag, and the socket
  # unit runs `systemctl --user set-environment SSH_AUTH_SOCK=%t/gcr/ssh` in
  # ExecStartPost. That would shadow the Bitwarden agent socket that
  # home/andongni.nix puts in SSH_AUTH_SOCK, so keep the keyring's secrets
  # component without letting it take over ssh.
  services.gnome.gcr-ssh-agent.enable = false;

  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
}
