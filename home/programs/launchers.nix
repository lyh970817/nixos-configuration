{ pkgs, ... }:

let
  codexLauncher = pkgs.writeShellScript "launch-codex" ''
    exec ${pkgs.alacritty}/bin/alacritty --class Codex,codex --command ${pkgs.zsh}/bin/zsh -lc 'exec codex'
  '';
in
{
  xdg.dataFile = {
    "applications/firefox.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Firefox
        GenericName=Web Browser
        Comment=Browse the Web
        Exec=${pkgs.firefox}/bin/firefox %U
        Icon=firefox
        Terminal=false
        Categories=Network;WebBrowser;
        MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;
        StartupNotify=true
        StartupWMClass=firefox
        Keywords=web;browser;internet;
      '';
    };

    "applications/uuctl.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=uuctl
      Hidden=true
    '';

    "applications/codex.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Codex
        GenericName=AI Coding Agent
        Comment=OpenAI Codex terminal coding agent
        Exec=${codexLauncher}
        Icon=utilities-terminal
        Terminal=false
        Categories=Development;Utility;
        StartupNotify=true
        StartupWMClass=codex
        TryExec=${pkgs.codex}/bin/codex
        Keywords=openai;codex;agent;ai;coding;terminal;
      '';
    };
  };

  xdg.desktopEntries = {
    "115browser" = {
      name = "115 Browser";
      genericName = "Web Browser";
      comment = "115 cloud storage desktop client";
      exec = "${pkgs."115browser"}/bin/115browser %U";
      icon = "115browser";
      terminal = false;
      type = "Application";
      categories = [
        "Network"
        "WebBrowser"
        "FileTransfer"
      ];
      startupNotify = true;
      settings = {
        Keywords = "115;browser;cloud;drive;sync;";
        StartupWMClass = "115Browser";
      };
    };

    baidunetdisk = {
      name = "Baidu Netdisk";
      genericName = "Cloud Storage";
      comment = "Baidu cloud storage client";
      exec = "${pkgs.nur.repos.xddxdd.baidunetdisk}/bin/baidunetdisk %U";
      icon = "baidunetdisk";
      terminal = false;
      type = "Application";
      categories = [
        "Network"
        "FileTransfer"
      ];
      startupNotify = true;
      settings = {
        Keywords = "baidu;netdisk;cloud;drive;sync;";
        StartupWMClass = "baidunetdisk";
      };
    };

    wemeetapp = {
      name = "Tencent Meeting";
      genericName = "Video Conference";
      comment = "Tencent Meeting desktop client";
      exec = "${pkgs.wemeet}/bin/wemeet %u";
      icon = "wemeet";
      terminal = false;
      type = "Application";
      categories = [
        "AudioVideo"
        "Network"
      ];
      startupNotify = true;
      mimeType = [ "x-scheme-handler/wemeet" ];
      settings = {
        Keywords = "tencent;meeting;wemeet;conference;video;";
      };
    };

    hibernate = {
      name = "Hibernate";
      genericName = "System";
      comment = "Hibernate the system";
      exec = "systemctl hibernate";
      icon = "system-suspend-hibernate";
      terminal = false;
      type = "Application";
      categories = [ "System" ];
      settings = {
        Keywords = "suspend;sleep;disk;";
      };
    };

    reboot = {
      name = "Reboot";
      genericName = "System";
      comment = "Restart the computer";
      exec = "systemctl reboot";
      icon = "system-reboot";
      terminal = false;
      categories = [
        "System"
        "Utility"
      ];
      settings = {
        Keywords = "restart;reset;power;";
      };
    };

    shutdown = {
      name = "Shutdown";
      genericName = "System";
      comment = "Power off the computer immediately";
      exec = "systemctl poweroff";
      icon = "system-shutdown";
      terminal = false;
      categories = [
        "System"
        "Utility"
      ];
      settings = {
        Keywords = "power;off;halt;stop;";
      };
    };

    darkman-toggle = {
      name = "Toggle darkman";
      genericName = "Toggle dark mode";
      comment = "Toggle dark mode via darkman";
      exec = "darkman toggle";
      terminal = false;
      type = "Application";
      categories = [ "Settings" ];
      noDisplay = true;
      settings = {
        TryExec = "darkman";
        Keywords = "dark;light;colour-preference;theme;";
      };
    };

    lvim = {
      name = "LunarVim";
      genericName = "Text Editor";
      comment = "An IDE layer for Neovim with sane defaults";
      exec = "lvim %F";
      terminal = true;
      type = "Application";
      icon = "lvim";
      categories = [
        "Utility"
        "TextEditor"
      ];
      startupNotify = false;
      mimeType = [
        "text/english"
        "text/plain"
        "text/x-makefile"
        "text/x-c++hdr"
        "text/x-c++src"
        "text/x-chdr"
        "text/x-csrc"
        "text/x-java"
        "text/x-moc"
        "text/x-pascal"
        "text/x-tcl"
        "text/x-tex"
        "application/x-shellscript"
        "text/x-c"
        "text/x-c++"
      ];
      settings = {
        TryExec = "lvim";
        Keywords = "Text;editor;";
      };
    };
  };
}
