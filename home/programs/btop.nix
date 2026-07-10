# Btop system monitor
# Theme switching is handled by darkman through the current.theme symlink.
{ ... }:

{
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "current";
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
}
