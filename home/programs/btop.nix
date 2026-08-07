# Btop system monitor
# Theme follows the per-session THEME_MODE env var (dark|light), read at launch
# by the wrapper below. When THEME_MODE isn't set (e.g. the systemd-launched
# btop dashboard), the wrapper falls back to this machine's own desktop mode
# by reading the hypr current-theme symlink directly. There is no btop-level
# theme symlink: btop is invoked with -c pointing at whichever of
# btop-dark.conf / btop-light.conf matches the resolved mode.
{ pkgs, ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

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
      # THEME_MODE set: a session (interactive shell, mosh/ssh peer) owns
      # its own colours (Layer B) - use it as-is (coerced below).
      # THEME_MODE unset: follow this machine's own monitor (Layer A) by
      # reading the hypr current-theme symlink directly, inline, rather than
      # shelling out to theme-mode - a systemd user service has no
      # guaranteed PATH, which is exactly the failure mode being avoided.
      # Callers that are part of the desktop environment (not a session)
      # clear THEME_MODE deliberately to select this path - see
      # dotfiles/hypr/scripts/btop-dashboard.sh.
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
      vt220-amber = ''
        theme[main_bg]="#${p.background}"
        theme[main_fg]="#${p.foreground}"
        theme[title]="#${p.foreground}"
        theme[hi_fg]="#${p.foreground}"
        theme[selected_bg]="#${p.secondaryText}"
        theme[selected_fg]="#${p.background}"
        theme[inactive_fg]="#${p.subtleBorder}"
        theme[graph_text]="#${p.accent}"
        theme[meter_bg]="#${p.deepSurface}"
        theme[proc_misc]="#${p.mutedText}"
        theme[cpu_box]="#${p.foreground}"
        theme[mem_box]="#${p.accent}"
        theme[net_box]="#${p.secondaryText}"
        theme[proc_box]="#${p.foreground}"
        theme[div_line]="#${p.subtleBorder}"
        theme[temp_start]="#${p.subtleBorder}"
        theme[temp_mid]="#${p.secondaryText}"
        theme[temp_end]="#${p.foreground}"
        theme[cpu_start]="#${p.subtleBorder}"
        theme[cpu_mid]="#${p.secondaryText}"
        theme[cpu_end]="#${p.foreground}"
        theme[free_start]="#${p.subtleBorder}"
        theme[free_mid]="#${p.mutedText}"
        theme[free_end]="#${p.secondaryText}"
        theme[cached_start]="#${p.subtleBorder}"
        theme[cached_mid]="#${p.mutedText}"
        theme[cached_end]="#${p.accent}"
        theme[available_start]="#${p.subtleBorder}"
        theme[available_mid]="#${p.secondaryText}"
        theme[available_end]="#${p.foreground}"
        theme[used_start]="#${p.mutedText}"
        theme[used_mid]="#${p.accent}"
        theme[used_end]="#${p.foreground}"
        theme[download_start]="#${p.subtleBorder}"
        theme[download_mid]="#${p.secondaryText}"
        theme[download_end]="#${p.foreground}"
        theme[upload_start]="#${p.deepSurface}"
        theme[upload_mid]="#${p.mutedText}"
        theme[upload_end]="#${p.accent}"
        theme[process_start]="#${p.foreground}"
        theme[process_mid]="#${p.secondaryText}"
        theme[process_end]="#${p.subtleBorder}"
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

  xdg.configFile."btop/btop-dark.conf".text = mkBtopConfig "vt220-amber";
  xdg.configFile."btop/btop-light.conf".text = mkBtopConfig "eink";
}
