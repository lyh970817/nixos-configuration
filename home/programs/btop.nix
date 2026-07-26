# Btop system monitor
# Theme follows the per-session THEME_MODE env var (dark|light), read at launch
# by the wrapper below. When THEME_MODE isn't set (e.g. the systemd-launched
# btop dashboard), the wrapper falls back to this machine's own desktop mode
# by reading the hypr current-theme symlink directly. There is no btop-level
# theme symlink: btop is invoked with -c pointing at whichever of
# btop-dark.conf / btop-light.conf matches the resolved mode.
{ pkgs, ... }:

let
  # Settings shared by both dark and light configs. Only color_theme differs
  # between the two variants (see mkBtopConfig below).
  commonSettings = {
    theme_background = false;
    truecolor = true;
    vim_keys = true;
    rounded_corners = true;
    graph_symbol = "braille";
    update_ms = 1500;
    proc_sorting = "cpu lazy";
    proc_tree = false;
    proc_colors = true;
    proc_gradient = true;
    show_battery = true;
    show_disks = true;
    only_physical = true;
    use_fstab = false;
  };

  # Render a single btop.conf value: bools as True/False, strings quoted,
  # everything else (ints) bare.
  renderValue =
    v:
    if builtins.isBool v then
      (if v then "True" else "False")
    else if builtins.isString v then
      ''"${v}"''
    else
      toString v;

  # Render a full attrset as btop's `key = value` config format.
  renderConfig =
    settings:
    builtins.concatStringsSep "\n" (
      builtins.attrValues (builtins.mapAttrs (name: value: "${name} = ${renderValue value}") settings)
    )
    + "\n";

  mkBtopConfig = colorTheme: renderConfig (commonSettings // { color_theme = colorTheme; });

  # Wrap btop so it always launches with the config matching the session's
  # THEME_MODE, defaulting to dark when THEME_MODE is set but not exactly
  # dark/light. Calls btop's store path directly (never a bare `btop`) to
  # avoid PATH recursion, and is a real executable so it works regardless of
  # what launches it (Hyprland binds, tmux panes, btop-workspace).
  btopWrapped = pkgs.symlinkJoin {
    name = "btop-wrapped";
    paths = [ pkgs.btop ];
    postBuild = ''
      rm "$out/bin/btop"
      cat > "$out/bin/btop" <<'WRAPPER'
      #!/usr/bin/env bash
      # THEME_MODE set: a session (interactive shell, mosh/ssh peer) is
      # authoritative for its own colours - use it as-is (coerced below).
      # THEME_MODE unset: a non-shell launch (systemd user service, a
      # Hyprland bind run outside a session) with no session to inherit
      # from, so fall back to this machine's own desktop mode (Layer A) by
      # reading the hypr current-theme symlink directly, inline, rather than
      # shelling out to theme-mode - a systemd user service has no
      # guaranteed PATH, which is exactly the failure mode being avoided.
      mode="$THEME_MODE"
      if [ -z "$mode" ]; then
        case "$(readlink "$HOME/.local/state/hypr/current-theme.conf" 2>/dev/null)" in
          *dark.conf) mode=dark ;;
          *) mode=light ;;
        esac
      fi
      case "$mode" in
        dark | light) ;;
        *) mode=dark ;;
      esac
      exec ${pkgs.btop}/bin/btop -c "$HOME/.config/btop/btop-$mode.conf" "$@"
      WRAPPER
      chmod +x "$out/bin/btop"
    '';
  };
in
{
  programs.btop = {
    enable = true;
    package = btopWrapped;

    themes = {
      matrix = ''
        theme[main_bg]="#000000"
        theme[main_fg]="#4AB34D"
        theme[title]="#4AB34D"
        theme[hi_fg]="#4AB34D"
        theme[selected_bg]="#2E9031"
        theme[selected_fg]="#000000"
        theme[inactive_fg]="#126D15"
        theme[graph_text]="#3CA23F"
        theme[meter_bg]="#045C07"
        theme[proc_misc]="#207F23"
        theme[cpu_box]="#4AB34D"
        theme[mem_box]="#3CA23F"
        theme[net_box]="#2E9031"
        theme[proc_box]="#4AB34D"
        theme[div_line]="#126D15"
        theme[temp_start]="#126D15"
        theme[temp_mid]="#2E9031"
        theme[temp_end]="#4AB34D"
        theme[cpu_start]="#126D15"
        theme[cpu_mid]="#2E9031"
        theme[cpu_end]="#4AB34D"
        theme[free_start]="#126D15"
        theme[free_mid]="#207F23"
        theme[free_end]="#2E9031"
        theme[cached_start]="#126D15"
        theme[cached_mid]="#207F23"
        theme[cached_end]="#3CA23F"
        theme[available_start]="#126D15"
        theme[available_mid]="#2E9031"
        theme[available_end]="#4AB34D"
        theme[used_start]="#207F23"
        theme[used_mid]="#3CA23F"
        theme[used_end]="#4AB34D"
        theme[download_start]="#126D15"
        theme[download_mid]="#2E9031"
        theme[download_end]="#4AB34D"
        theme[upload_start]="#045C07"
        theme[upload_mid]="#207F23"
        theme[upload_end]="#3CA23F"
        theme[process_start]="#4AB34D"
        theme[process_mid]="#2E9031"
        theme[process_end]="#126D15"
      '';

      eink = ''
        theme[main_bg]="#FFFFFF"
        theme[main_fg]="#000000"
        theme[title]="#000000"
        theme[hi_fg]="#000000"
        theme[selected_bg]="#000000"
        theme[selected_fg]="#FFFFFF"
        theme[inactive_fg]="#808080"
        theme[graph_text]="#000000"
        theme[meter_bg]="#D0D0D0"
        theme[proc_misc]="#404040"
        theme[cpu_box]="#000000"
        theme[mem_box]="#000000"
        theme[net_box]="#000000"
        theme[proc_box]="#000000"
        theme[div_line]="#808080"
        theme[temp_start]="#B0B0B0"
        theme[temp_mid]="#606060"
        theme[temp_end]="#000000"
        theme[cpu_start]="#B0B0B0"
        theme[cpu_mid]="#606060"
        theme[cpu_end]="#000000"
        theme[free_start]="#D0D0D0"
        theme[free_mid]="#A0A0A0"
        theme[free_end]="#707070"
        theme[cached_start]="#C0C0C0"
        theme[cached_mid]="#808080"
        theme[cached_end]="#404040"
        theme[available_start]="#B0B0B0"
        theme[available_mid]="#606060"
        theme[available_end]="#000000"
        theme[used_start]="#A0A0A0"
        theme[used_mid]="#505050"
        theme[used_end]="#000000"
        theme[download_start]="#B0B0B0"
        theme[download_mid]="#606060"
        theme[download_end]="#000000"
        theme[upload_start]="#D0D0D0"
        theme[upload_mid]="#808080"
        theme[upload_end]="#303030"
        theme[process_start]="#000000"
        theme[process_mid]="#505050"
        theme[process_end]="#A0A0A0"
      '';
    };
  };

  xdg.configFile."btop/btop-dark.conf".text = mkBtopConfig "matrix";
  xdg.configFile."btop/btop-light.conf".text = mkBtopConfig "eink";
}
