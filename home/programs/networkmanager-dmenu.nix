{ config, pkgs, ... }:

{
  home.packages = [ pkgs.networkmanager_dmenu ];

  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = ${config.programs.rofi.package}/bin/rofi -i
    prompt = Networks

    [dmenu_passphrase]
    obscure = True

    [editor]
    terminal = ${pkgs.kitty}/bin/kitty
    gui_if_available = True
    gui = ${pkgs.networkmanagerapplet}/bin/nm-connection-editor
  '';

  # Override the package entry so the network picker has one searchable name.
  xdg.dataFile."applications/networkmanager_dmenu.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Wi-Fi networks
      GenericName=System
      Comment=Find Wi-Fi networks and connect with your password
      Exec=${pkgs.networkmanager_dmenu}/bin/networkmanager_dmenu
      Icon=network-wireless
      Terminal=false
      Categories=Network;Settings;
      Keywords=wifi;wi-fi;wireless;network;connect;password;authentication;
    '';
  };
}
