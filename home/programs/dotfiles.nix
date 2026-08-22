{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  role = osConfig.portable.role;
  peerHost = osConfig.portable.peerHost;

  # Wrapper baked with the peer host. Retries an SSH Herdr session to the home
  # box a few times; if home is unreachable (or no peer configured) it falls
  # back to a local shell so the floating window lands at a usable prompt
  # instead of closing.
  homeTerminal = pkgs.writeShellApplication {
    name = "home-terminal";
    runtimeInputs = [
      pkgs.openssh
      pkgs.coreutils
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}

      if [ -z "$PEER" ]; then
        exec "''${SHELL:-${pkgs.bash}/bin/bash}"
      fi

      for _ in 1 2 3; do
        # shellcheck disable=SC2016 # The single-quoted script expands $SHELL on the remote host.
        if ssh -t "$PEER" '
          if command -v remote-herdr-client >/dev/null 2>&1 && remote-herdr-client; then
            exit 0
          fi
          if command -v tmux >/dev/null 2>&1; then
            export THEME_MODE=dark
            exec tmux new-session -A -d -s remote -e THEME_MODE=dark ";" attach -t remote
          fi
          exec "''${SHELL:-${pkgs.runtimeShell}}" -l
        '; then
          exit 0
        fi
        sleep 2
      done

      # Home unreachable/offline: fall back to a local shell.
      exec "''${SHELL:-${pkgs.bash}/bin/bash}"
    '';
  };

  # Attaches (or creates) the local 'remote' Herdr session — the one SSH
  # sessions from the laptop land in — from a terminal launched right here on
  # home. Non-modal: Super+Enter keeps meaning "my local session"; this is a
  # separate, deliberate action for the rare occasion of walking over to the
  # home desk and wanting to see what the laptop session was doing.
  #
  # This is an independent dark session, regardless of the light home desktop
  # or the laptop's current desktop mode. It deliberately bypasses
  # remote-herdr-client, so viewing the session locally never makes openers
  # think a remote viewer is attached.
  attachRemote = pkgs.writeShellApplication {
    name = "attach-remote";
    runtimeInputs = [ pkgs.herdr ];
    text = ''
      export THEME_MODE=dark
      exec herdr --session remote
    '';
  };

  # The nvim-treesitter plugin (main branch, pinned in
  # dotfiles/nvim/lazy-lock.json) ships latex queries written for the grammar
  # rev its own lockfile pins; nixpkgs' older 7e0ecdc parser lacks nodes like
  # curly_group_text, so highlights.scm fails with "Impossible pattern" on
  # every markdown buffer containing math. Rebuild the grammar at the plugin's
  # pinned rev (lockfile.json in the lazy-installed plugin) with the same
  # nixpkgs builder; bump this rev when a lazy-lock.json update moves the
  # plugin's latex pin.
  latexGrammar = pkgs.vimPlugins.nvim-treesitter.builtGrammars.latex.overrideAttrs {
    version = "0.0.0+rev=7b06f6e";
    src = pkgs.fetchFromGitHub {
      owner = "latex-lsp";
      repo = "tree-sitter-latex";
      rev = "7b06f6ed394308e7407a1703d2724128c45fc9d7";
      hash = "sha256-HbRjblLBExpBkBBjHyEHfnK0oootjAsqkwjmGH3/UYI=";
    };
  };

  # Lua fragment included by dotfiles/hypr/hyprland.lua. The Hyprland .conf
  # format is removed in 0.57, so this is Lua rather than keyword lines.
  roleLua =
    if role == "remote" then
      ''
        -- Remote role: Super+Enter and boot connect to the home box; Super+Shift+Enter opens local Herdr.
        local onHyprlandStart = ...
        hl.bind("SUPER + Return", hl.dsp.exec_cmd("btop-workspace exec foot --app-id foot-float home-terminal"))
        hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("btop-workspace exec foot --app-id foot-float herdr"))
        onHyprlandStart(function()
          hl.exec_cmd("btop-workspace exec foot --app-id foot-float home-terminal")
        end)
        -- Remote laptop: lid close turns the screen off via DPMS without
        -- suspending. logind ignores the lid; see modules/system/lid.nix.
        hl.bind("switch:on:Lid Switch", hl.dsp.dpms({ action = "off" }), { locked = true })
        hl.bind("switch:off:Lid Switch", hl.dsp.dpms({ action = "on" }), { locked = true })
        -- Manual escape hatch for the DPMS-off state. Nothing else restores the
        -- panel: there is no idle daemon here, so a bouncy lid sensor that
        -- reports a close without the matching open leaves the screen dark
        -- indefinitely. Fn+F12 is the only Fn combo the X30W-K emits that
        -- nothing binds — it arrives as a plain AT KEY_SCROLLLOCK (code 70)
        -- that keyd forwards untouched, and Scroll_Lock is in no modifier_map
        -- in the us layout, so it cannot latch a modifier. Deliberately "on"
        -- only, never a toggle: a toggle here could blank the screen and would
        -- then be the only way out.
        hl.bind("Scroll_Lock", hl.dsp.dpms({ action = "on" }), { locked = true })
        -- Remote laptop: every external output mirrors the built-in panel.
        -- eDP-1 is the one screen being looked at, so a second display is
        -- always a duplicate of it rather than extra desk space. Listed per
        -- connector (the X30W-K exposes exactly these three) because a
        -- catch-all output = "" would also match eDP-1 and ask it to mirror
        -- itself.
        for _, output in ipairs({ "HDMI-A-1", "DP-1", "DP-2" }) do
          hl.monitor({ output = output, mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1" })
        end
        -- Re-assert the e-ink panel's own rule, which hyprland.lua sets before
        -- it includes this file. Measured on Hyprland 0.56.1: the LAST matching
        -- monitor rule wins, with no precedence for desc: over a connector
        -- name. Without this line the mirror rules above would capture the
        -- Paperlike whenever it lands on one of those three connectors, costing
        -- both its native mode and the light-mode trigger that
        -- scripts/monitor-switch.sh derives from its presence. Keep identical
        -- to the copy in dotfiles/hypr/hyprland.lua.
        hl.monitor({
          output = "desc:DSC Paperlike H D",
          mode = "2200x1650@40",
          position = "0x0",
          scale = 1.666667,
        })
      ''
    else
      ''
        -- Home role: Super+Enter attaches to the 'main' tmux session, Super+Shift+Enter opens 'secondary', Super+Ctrl+Enter attaches the laptop's remote Herdr session.
        hl.bind("SUPER + Return", hl.dsp.exec_cmd("btop-workspace exec foot --app-id foot-float tmux new-session -A -s main"))
        hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("btop-workspace exec foot --app-id foot-float tmux new-session -A -s secondary"))
        hl.bind("SUPER + CTRL + Return", hl.dsp.exec_cmd("btop-workspace exec foot --app-id foot-float attach-remote"))
      '';

  # TRANSITIONAL twin of roleLua in the legacy hyprlang format, for a
  # compositor that started before the migration and therefore cannot load Lua.
  # See the header of ../../dotfiles/hypr/hyprland.conf for why a frozen legacy
  # set cannot drift, and for the condition under which all of this is deleted.
  #
  # Both fragments are generated from the same `role` here, in the same `let`,
  # so the one thing about them that does vary per machine cannot disagree
  # between the two dialects.
  roleConf =
    if role == "remote" then
      ''
        # Remote role: Super+Enter and boot connect to the home box; Super+Shift+Enter opens local Herdr.
        bind = $mainMod, Return, exec, btop-workspace exec foot --app-id foot-float home-terminal
        bind = $mainMod SHIFT, Return, exec, btop-workspace exec foot --app-id foot-float herdr
        exec-once = ~/.config/hypr/scripts/run-session-startup.sh btop-workspace exec foot --app-id foot-float home-terminal
        # Remote laptop: lid close turns the screen off via DPMS without
        # suspending. logind ignores the lid; see modules/system/lid.nix.
        bindl = , switch:on:Lid Switch, exec, hyprctl dispatch dpms off
        bindl = , switch:off:Lid Switch, exec, hyprctl dispatch dpms on
        # Manual escape hatch for the DPMS-off state. Nothing else restores the
        # panel: there is no idle daemon here, so a bouncy lid sensor that
        # reports a close without the matching open leaves the screen dark
        # indefinitely. Fn+F12 is the only Fn combo the X30W-K emits that
        # nothing binds -- it arrives as a plain AT KEY_SCROLLLOCK (code 70)
        # that keyd forwards untouched, and Scroll_Lock is in no modifier_map
        # in the us layout, so it cannot latch a modifier. Deliberately "on"
        # only, never a toggle: a toggle here could blank the screen and would
        # then be the only way out.
        bindl = , Scroll_Lock, exec, hyprctl dispatch dpms on
        # Remote laptop: every external output mirrors the built-in panel; see
        # the roleLua twin for why the connectors are listed one by one and why
        # the Paperlike rule is repeated after them.
        monitor = HDMI-A-1,preferred,auto,1,mirror,eDP-1
        monitor = DP-1,preferred,auto,1,mirror,eDP-1
        monitor = DP-2,preferred,auto,1,mirror,eDP-1
        monitor = desc:DSC Paperlike H D,2200x1650@40,0x0,1.666667
      ''
    else
      ''
        # Home role: Super+Enter attaches to the 'main' tmux session, Super+Shift+Enter opens 'secondary', Super+Ctrl+Enter attaches the laptop's remote Herdr session.
        bind = $mainMod, Return, exec, btop-workspace exec foot --app-id foot-float tmux new-session -A -s main
        bind = $mainMod SHIFT, Return, exec, btop-workspace exec foot --app-id foot-float tmux new-session -A -s secondary
        bind = $mainMod CTRL, Return, exec, btop-workspace exec foot --app-id foot-float attach-remote
      '';
in
{
  home.packages = [
    homeTerminal
    attachRemote
  ];

  xdg.configFile = {
    # Recursive so the colorscheme generated by programs/nvim-theme.nix can
    # live alongside the symlinked tree.
    "nvim" = {
      source = ../../dotfiles/nvim;
      recursive = true;
    };
    # Prebuilt latex tree-sitter parser on the runtimepath. The latex grammar
    # has no generated parser.c upstream, and :TSInstall latex breaks with
    # tree-sitter CLI 0.26.9 (it removed the `--no-bindings` flag
    # nvim-treesitter passes to `tree-sitter generate`), so Nix supplies the
    # compiled parser instead; dotfiles/nvim/lua/plugins/treesitter.lua keeps
    # latex out of ensure_installed/TSUpdate. The rev is overridden above to
    # match the plugin's queries.
    "nvim/parser/latex.so".source = "${latexGrammar}/parser";
    # Recursive so the generated role.lua can live alongside the symlinked tree.
    "hypr" = {
      source = ../../dotfiles/hypr;
      recursive = true;
    };
    "hypr/role.lua".text = roleLua;
    # TRANSITIONAL: see roleConf above.
    "hypr/role.conf".text = roleConf;
    # Shell-sourceable twin of role.lua so plain dotfile scripts (which are
    # deployed verbatim and cannot be templated) can branch on the role.
    "hypr/role.env".text = ''
      HYPR_ROLE=${role}
    '';
    # Recursive so the flavor generated by programs/yazi-theme.nix can live
    # alongside the symlinked tree.
    "yazi" = {
      source = ../../dotfiles/yazi;
      recursive = true;
    };
    "znt".source = ../../dotfiles/znt;
  };
}
