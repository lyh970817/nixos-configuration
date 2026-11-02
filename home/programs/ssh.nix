{
  lib,
  osConfig,
  ...
}:

let
  peerHost = osConfig.portable.peerHost;
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "create" = {
        hostname = "hpc.create.kcl.ac.uk";
        user = "k1764630";
        identityFile = "~/.ssh/id_ed25519";
        # One multiplexed connection: the first ssh/scp authenticates (MFA) and
        # stays open in the background; every later command rides on it, so
        # repeated one-off commands neither re-check MFA nor count against the
        # login node's MaxStartups throttle. `ssh -O check create` shows it,
        # `ssh -O exit create` closes it.
        controlMaster = "auto";
        controlPath = "~/.ssh/cm-%C";
        controlPersist = "4h";
        serverAliveInterval = 60;
      };
    }
    // lib.optionalAttrs (peerHost != "") {
      # The peer is reached over Tailscale SSH, where the host key is generated
      # by tailscaled rather than by an sshd on disk: it changes whenever the
      # node is re-added to the tailnet, and the name can pick up a "-1" suffix
      # in the same event. A pinned or missing known_hosts entry then turns into
      # a hard failure for the unattended callers (theme-push, yazi-open-image),
      # which have no way to answer a prompt. Accepting a first-seen key is safe
      # here because the peer's identity is already enforced by the tailnet, not
      # by this key. The bare name and the MagicDNS FQDN both match.
      "${peerHost} ${peerHost}.*" = {
        extraOptions.StrictHostKeyChecking = "accept-new";
      };
    };
  };
}
