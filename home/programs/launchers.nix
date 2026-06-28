{ pkgs, ... }:

{
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

    openwhispr = {
      name = "OpenWhispr";
      genericName = "Voice Dictation";
      comment = "Voice-to-text dictation, transcription, notes, and AI actions";
      exec = "${pkgs.openwhispr}/bin/openwhispr";
      icon = "audio-input-microphone";
      terminal = false;
      type = "Application";
      categories = [
        "AudioVideo"
        "Office"
        "Utility"
      ];
      startupNotify = true;
      settings = {
        Keywords = "voice;dictation;speech;transcription;whisper;";
        StartupWMClass = "OpenWhispr";
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

  xdg.configFile."autostart/openwhispr.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=OpenWhispr
    GenericName=Voice Dictation
    Comment=Voice-to-text dictation, transcription, notes, and AI actions
    Exec=${pkgs.openwhispr}/bin/openwhispr
    Icon=audio-input-microphone
    Terminal=false
    Categories=AudioVideo;Office;Utility;
    StartupNotify=true
    StartupWMClass=OpenWhispr
    Keywords=voice;dictation;speech;transcription;whisper;
  '';
}
