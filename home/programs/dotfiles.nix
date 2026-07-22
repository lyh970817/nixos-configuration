{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  role = osConfig.portable.role;
  peerHost = osConfig.portable.peerHost;

  # Wrapper baked with the peer host. Retries a mosh tmux session to the home
  # box a few times; if home is unreachable (or no peer configured) it falls
  # back to a local shell so the floating window lands at a usable prompt
  # instead of closing.
  homeTerminal = pkgs.writeShellApplication {
    name = "home-terminal";
    runtimeInputs = [ pkgs.mosh ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}

      if [ -z "$PEER" ]; then
        exec "''${SHELL:-${pkgs.bash}/bin/bash}"
      fi

      for _ in 1 2 3; do
        # Adaptive prediction disables local echo on fast links; force it on.
        if mosh --predict=always --predict-overwrite "$PEER" -- tmux new-session -A -s main; then
          exit 0
        fi
        sleep 2
      done

      # Home unreachable/offline: fall back to a local shell.
      exec "''${SHELL:-${pkgs.bash}/bin/bash}"
    '';
  };

  roleConf =
    if role == "remote" then
      ''
        # Remote role: Super+Enter and boot connect to the home box; Super+Shift+Enter is a local tmux session.
        bind = $mainMod, Return, exec, btop-workspace exec alacritty --class Alacritty-float --command home-terminal
        bind = $mainMod SHIFT, Return, exec, btop-workspace exec alacritty --class Alacritty-float --command tmux new-session -A -s main
        exec-once = btop-workspace exec alacritty --class Alacritty-float --command home-terminal
      ''
    else
      ''
        # Home role: Super+Enter attaches to the 'main' tmux session, Super+Shift+Enter opens 'secondary'.
        bind = $mainMod, Return, exec, btop-workspace exec alacritty --class Alacritty-float --command tmux new-session -A -s main
        bind = $mainMod SHIFT, Return, exec, btop-workspace exec alacritty --class Alacritty-float --command tmux new-session -A -s secondary
      '';
in
{
  home.packages = [ homeTerminal ];

  xdg.configFile = {
    "nvim".source = ../../dotfiles/nvim;
    # Recursive so the generated role.conf can live alongside the symlinked tree.
    "hypr" = {
      source = ../../dotfiles/hypr;
      recursive = true;
    };
    "hypr/role.conf".text = roleConf;
    "yazi".source = ../../dotfiles/yazi;
    "znt".source = ../../dotfiles/znt;
  };
}
