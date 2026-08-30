{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable graphics acceleration
  # No GPU-specific video driver is forced; Mesa/DRM autodetect per machine.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    # VA-API userspace driver for the remote laptop's Intel iGPU (Alder Lake-P
    # GT2 / Iris Xe, 8086:46a6, i5-1240P). Mesa ships radeonsi, which covers
    # the home desktop's amdgpu, but no Intel VA-API driver -- so without this
    # the laptop has no hardware video encoder at all and screen-record falls
    # back to its CPU encoder. Gen12/Xe is far past the Broadwell cutoff, so
    # it wants intel-media-driver (iHD), not the legacy intel-vaapi-driver
    # (i965).
    #
    # Role-gated rather than unconditional because the home desktop is AMD and
    # would carry the package for nothing, and rather than a portable.quirks.*
    # entry because this is ordinary hardware enablement, not a workaround for
    # a defect in one chassis -- and a quirk would live in the untracked
    # local.nix, where a fresh remote install would silently lack it. Revisit
    # if the remote role ever moves to non-Intel hardware.
    extraPackages = lib.optionals (config.portable.role != "home") [
      pkgs.intel-media-driver
    ];
  };
}
