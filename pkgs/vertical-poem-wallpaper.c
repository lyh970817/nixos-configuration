#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
#include <stdlib.h>

static GtkWidget *poem_column(const char *text) {
  GtkWidget *label = gtk_label_new(text);
  gtk_label_set_justify(GTK_LABEL(label), GTK_JUSTIFY_CENTER);
  gtk_widget_set_halign(label, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(label, GTK_ALIGN_CENTER);
  return label;
}

int main(int argc, char **argv) {
  int font_size = 24;
  if (argc > 1) {
    char *end = NULL;
    long requested_size = strtol(argv[1], &end, 10);
    if (*argv[1] == '\0' || *end != '\0' || requested_size < 12 ||
        requested_size > 72) {
      g_printerr("font size must be an integer from 12 to 72\n");
      return 2;
    }
    font_size = (int)requested_size;
  }

  gtk_init(&argc, &argv);

  GtkWindow *window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_layer_init_for_window(window);
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_BACKGROUND);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_set_exclusive_zone(window, 0);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);

  GtkCssProvider *css = gtk_css_provider_new();
  gchar *stylesheet = g_strdup_printf(
      "window { background: #050806; }"
      "label { color: #4BAE55; font-family: 'Noto Sans Mono CJK TC'; "
      "font-size: %dpt; font-weight: 400; }",
      font_size);
  gtk_css_provider_load_from_data(
      css, stylesheet, -1, NULL);
  g_free(stylesheet);
  gtk_style_context_add_provider_for_screen(
      gdk_screen_get_default(), GTK_STYLE_PROVIDER(css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(css);

  GtkWidget *columns = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 64);
  gtk_widget_set_halign(columns, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(columns, GTK_ALIGN_CENTER);
  gtk_box_pack_start(GTK_BOX(columns), poem_column("此\n地\n空\n餘\n黃\n鶴\n樓"),
                     FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(columns), poem_column("昔\n人\n已\n乘\n黃\n鶴\n去"),
                     FALSE, FALSE, 0);

  gtk_container_add(GTK_CONTAINER(window), columns);
  g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
  gtk_widget_show_all(GTK_WIDGET(window));
  gtk_main();
  return 0;
}
