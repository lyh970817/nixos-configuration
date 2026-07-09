{ ... }:

{
  systemd.user.tmpfiles.rules = [
    "d %h/.scratch 0700 - - -"
  ];
}
