#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "file_open_portal.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Launch background of lib/ui/launch/launch_tokens.dart (LaunchPalette).
static const char* kLaunchBackgroundLight = "#F7F8FA";
static const char* kLaunchBackgroundDark = "#121418";

// Best-effort guess whether the desktop uses a dark theme.
static gboolean prefers_dark_theme() {
  GtkSettings* settings = gtk_settings_get_default();
  if (settings == nullptr) return FALSE;
  gboolean prefer_dark = FALSE;
  g_autofree gchar* theme_name = nullptr;
  g_object_get(settings, "gtk-application-prefer-dark-theme", &prefer_dark,
               "gtk-theme-name", &theme_name, nullptr);
  if (prefer_dark) return TRUE;
  if (theme_name == nullptr) return FALSE;
  g_autofree gchar* lower = g_ascii_strdown(theme_name, -1);
  return g_str_has_suffix(lower, "-dark") || g_str_has_suffix(lower, ":dark");
}

// Shows the window once Flutter has drawn the first frame of the launch
// animation, so it never appears empty or black (X11 and Wayland).
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen *screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
     const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
     if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
       use_header_bar = FALSE;
     }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Digitales Register");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }
  else {
    gtk_window_set_title(window, "Digitales Register");
  }

  gtk_window_set_title(window, "Digitales Register");
  gtk_window_set_icon_name(window, APPLICATION_ID);
  // The portable bundle must also have an icon without a desktop installation.
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon = g_build_filename(directory, "data", "icon.png", nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
  }
  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  // Fills gaps while the window is resized faster than Flutter redraws.
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, prefers_dark_theme()
                                        ? kLaunchBackgroundDark
                                        : kLaunchBackgroundLight);
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // The window stays hidden until the first frame; the view must be realized
  // to start rendering without being shown.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_file_open_portal(fl_engine_get_binary_messenger(fl_view_get_engine(view)));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar ***arguments, int *exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Match X11/Wayland window identity to the installed desktop entry.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("Digitales Register");
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
