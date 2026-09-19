# lsd as ls, themed through ANSI slots only, so it follows the phosphor
# profile (../palettes.nix) and the dark/light switch without a rebuild.
#
# Slots are chosen for the rung they carry in programs/foot.nix:
#
#   8   mutedText      dashes, tree edges, empty sizes
#   2   secondaryText  group, old dates, small sizes
#   4   accent         write bit, day-old dates, medium sizes
#   5   foreground     user, read bit
#   12  bright         exec bit, fresh dates, large sizes
#   10  hot            conflicts only
#
# Slots 7 and 15 are avoided: the light palette paints them white on white.
# File-type colours (directories, links, executables) are not settable here
# in lsd 1.2.0 -- the field is skipped and an entry for it voids the whole
# file -- and come from LS_COLORS in programs/shell.nix instead.
{ ... }:

{
  programs.lsd = {
    enable = true;
    colors = {
      user = 5;
      group = 2;
      permission = {
        read = 5;
        write = 4;
        exec = 12;
        exec-sticky = 12;
        no-access = 8;
        octal = 5;
        acl = 2;
        context = 2;
      };
      date = {
        hour-old = 12;
        day-old = 4;
        older = 2;
      };
      size = {
        none = 8;
        small = 2;
        medium = 4;
        large = 12;
      };
      inode = {
        valid = 2;
        invalid = 8;
      };
      links = {
        valid = 2;
        invalid = 8;
      };
      tree-edge = 8;
      git-status = {
        default = 8;
        unmodified = 8;
        ignored = 8;
        new-in-index = 12;
        new-in-workdir = 12;
        typechange = 4;
        deleted = 1;
        renamed = 4;
        modified = 4;
        conflicted = 10;
      };
    };
  };
}
