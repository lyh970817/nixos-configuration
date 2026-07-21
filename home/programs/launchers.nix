{ pkgs, ... }:
let
  # Package-provided .desktop entries the user hides from the rofi launcher to
  # declutter it. On the home machine these were hand-made override files in
  # ~/.local/share/applications that add NoDisplay=true; capture them here so
  # the same apps are hidden on every machine (fresh installs included), not
  # just wherever the hand-made file happened to exist. Each is a minimal
  # NoDisplay stub at the same basename, force = true so it wins over the
  # package's own entry (~/.local/share outranks the profile) -> single hidden
  # entry, no duplicate.
  hideFromLauncher = name: {
    name = "applications/${name}.desktop";
    value = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=${name}
        NoDisplay=true
      '';
    };
  };
  hiddenLauncherEntries = [
    # Upstream brave duplicate: nixpkgs brave ships two desktop files with the
    # same Name; com.brave.Browser's NoDisplay=true is misplaced upstream
    # inside a [Desktop Action] stanza so it never hides.
    "com.brave.Browser"
    "calibre-ebook-edit"
    "calibre-ebook-viewer"
    "calibre-lrfviewer"
    "cups"
    "darkman"
    "fcitx5-configtool"
    "htop"
    "kbd-layout-viewer5"
    "nixos-manual"
    "nvim"
    "org.fcitx.Fcitx5"
    "org.fcitx.fcitx5-migrator"
    "org.gnome.FileRoller"
    "rofi"
    "rofi-theme-selector"
    "thunar-bulk-rename"
    "thunar-settings"
  ];
in
{
  xdg.dataFile = builtins.listToAttrs (map hideFromLauncher hiddenLauncherEntries) // {
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

    # Network manager launcher: opens nmtui in a terminal. force = true so it
    # replaces any hand-made ~/.local/share/applications/nmtui.desktop instead
    # of showing as a second entry, and it lands on fresh installs too.
    "applications/nmtui.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Network Manager
        GenericName=Network Configuration
        Comment=Text-based network configuration tool
        Exec=alacritty --title nmtui -e zsh -i -c nmtui
        Icon=network-wired
        Terminal=false
        Categories=System;Network;Settings;
        Keywords=network;wifi;ethernet;connection;nmtui;
      '';
    };

    # Visible customizations of a package's own entry (renamed / simplified),
    # kept via a same-basename force override so they replace the package's
    # version rather than showing alongside it.
    "applications/teams-for-linux.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Version=1.5
        Name=Microsoft Teams
        GenericName=Collaboration Client
        Comment=Unofficial Microsoft Teams client for Linux
        Exec=teams-for-linux
        Icon=teams-for-linux
        Categories=Network;InstantMessaging;Chat;
      '';
    };

    "applications/calibre-gui.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Calibre
        GenericName=E-Book Library Management
        Comment=E-book library management: Convert, view, share, catalogue all your e-books
        TryExec=calibre
        Exec=calibre --detach %U
        Icon=calibre-gui
        Categories=Office;
        X-GNOME-UsesNotifications=true
        Keywords=epub;ebook;manager;
        MimeType=application/epub+zip;application/ereader;application/oebps-package+xml;application/pdf;application/vnd.ms-word.document.macroenabled.12;application/vnd.oasis.opendocument.text;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/x-cb7;application/x-cbc;application/x-cbr;application/x-cbz;application/x-mobi8-ebook;application/x-mobipocket-ebook;application/x-mobipocket-subscription;application/x-sony-bbeb;application/xhtml+xml;image/vnd.djvu;text/fb2+xml;text/html;text/plain;text/rtf;text/x-markdown;x-scheme-handler/calibre;
      '';
    };

    # Unique hand-made entry with no package equivalent: a claude-cli:// URI
    # handler, hidden from the launcher. Inert on machines without Claude Code.
    "applications/claude-code-url-handler.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Claude Code URL Handler
        Comment=Handle claude-cli:// deep links for Claude Code
        Exec="/home/andongni/.local/bin/claude" --handle-uri %u
        NoDisplay=true
        MimeType=x-scheme-handler/claude-cli;
      '';
    };

    # Package apps where the hand-made entry only adds a custom GenericName --
    # which the rofi launcher DOES display ("Name (GenericName)"), so it's a
    # visible difference, not cosmetic. Captured as force overrides so remote
    # matches home. Locale translation lines from the package entries are
    # dropped: the system locale is en_GB, so only the default fields render.
    "applications/bitwarden.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Bitwarden
        GenericName=Password Manager
        Comment=Secure and free password manager for all of your devices
        Exec=bitwarden %U
        Icon=bitwarden
        MimeType=x-scheme-handler/bitwarden
        Categories=Utility;
      '';
    };

    "applications/blueman-manager.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Bluetooth Manager
        GenericName=System
        Comment=Blueman Bluetooth Manager
        Exec=blueman-manager
        Icon=blueman
        Terminal=false
        StartupNotify=true
        Categories=GTK;GNOME;Settings;HardwareSettings;
      '';
    };

    "applications/LocalSend.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=LocalSend
        GenericName=Local File Transfer
        Exec=localsend_app %U
        Icon=localsend
        Keywords=Sharing;LAN;Files
        StartupNotify=true
        StartupWMClass=localsend_app
        Categories=GTK;FileTransfer;Utility;
      '';
    };

    "applications/sioyek.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Sioyek
        GenericName=PDF Viewr
        Comment=PDF viewer for reading research papers and technical books
        Keywords=pdf;viewer;reader;research;
        TryExec=sioyek
        Exec=sioyek %f
        StartupNotify=true
        Terminal=false
        Icon=sioyek-icon-linux
        Categories=Development;Viewer;
        MimeType=application/pdf;
      '';
    };

    "applications/yazi.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Yazi
        GenericName=File Manager
        Comment=Blazing fast terminal file manager written in Rust, based on async I/O
        Terminal=true
        TryExec=yazi
        Exec=yazi %u
        Icon=yazi
        MimeType=inode/directory
        Categories=Utility;Core;System;FileTools;FileManager;ConsoleOnly;
        Keywords=File;Manager;Explorer;Browser;Launcher
      '';
    };

    "applications/Zoom.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Zoom Workplace
        GenericName=Video Conference
        Comment=Zoom Video Conference
        Exec=zoom %U
        Icon=Zoom
        Terminal=false
        Encoding=UTF-8
        Categories=Network;Application;
        StartupWMClass=zoom
        MimeType=x-scheme-handler/zoommtg;x-scheme-handler/zoomus;x-scheme-handler/tel;x-scheme-handler/callto;x-scheme-handler/zoomphonecall;x-scheme-handler/zoomphonesms;x-scheme-handler/zoomcontactcentercall;application/x-zoom
        X-KDE-Protocols=zoommtg;zoomus;tel;callto;zoomphonecall;zoomphonesms;zoomcontactcentercall;
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
      comment = "An IDE layer for Neovim with sane defaults. Completely free and community driven.";
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
