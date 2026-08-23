{ pkgs, osConfig, ... }:

let
  # `login` opens a window on the host the browser runs on, which in an SSH
  # session is not the host the command was typed on. Baking the peer's name in
  # lets `kcl-fetch login --on` (no value) mean "the other machine".
  kclFetch = pkgs.callPackage ../../pkgs/kcl-fetch {
    peerHost = osConfig.portable.peerHost;
  };
in
{
  # The last rung of the paper ladder, below `scansci-oa` and `annas-books`:
  # the only route to paywalled work published after the shadow libraries
  # froze in 2021, and the only one that spends institutional credit. Every
  # request carries KCL's name, so the gate in `pkgs/kcl-fetch` -- one request
  # per second, one publisher at a time, ~25 per three hours, no batch mode at
  # all -- is the point of the package rather than a setting on it.
  #
  # Both roles: reading papers is as much a laptop activity as a desktop one,
  # and the browser profile is per-machine state that neither host shares.
  #
  # First use needs `kcl-fetch login` once: MFA (Microsoft Entra) is enforced,
  # so a human completes SSO in a visible window and the session is reused from
  # a dedicated Chromium profile under $XDG_DATA_HOME/kcl-fetch/profile until
  # it expires. That profile holds an institutional session and is deliberately
  # not the everyday browser profile.
  #
  # Signing in from an SSH session would paint that window on the far host's
  # screen, so `kcl-fetch login --on [HOST]` re-runs the sign-in over SSH on
  # HOST (default: the peer) against HOST's own profile. Sessions are never
  # copied between machines; each side signs in once for itself.
  #
  # Optional LibKey pre-check ("does KCL hold full text?"): write
  # {"library_id": "...", "token": "..."} to ~/.config/kcl-fetch/libkey with
  # mode 0600, or set $KCL_LIBKEY_LIBRARY_ID and $KCL_LIBKEY_TOKEN. Unset is a
  # supported state -- the check is skipped and the fetch proceeds.
  #
  # ~/.config/kcl-fetch/config.json can tighten the limits and nothing else;
  # any value that would loosen one is rejected at startup rather than clamped.
  #
  # $KCL_FETCH_CONTACT is unset by default and stays that way unless you want
  # it: setting it to an email address puts the (free, publisher-independent)
  # Crossref metadata lookup into their polite pool, at the cost of handing
  # that address to Crossref on every lookup.
  home.packages = [ kclFetch ];
}
