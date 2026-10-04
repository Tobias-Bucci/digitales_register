#include "file_open_portal.h"

#include <gio/gunixfdlist.h>
#include <glib/gstdio.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <functional>
#include <memory>
#include <string>

namespace {
constexpr char kDestination[] = "org.freedesktop.portal.Desktop";
constexpr char kPortalPath[] = "/org/freedesktop/portal/desktop";
constexpr char kRequestInterface[] = "org.freedesktop.portal.Request";

bool in_flatpak() {
  return g_getenv("FLATPAK_ID") != nullptr ||
         g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS);
}

// Console only. Do not render file paths, backend results or GError messages.
void portal_log(const char* stage, const std::string& handle = "",
                int code = -1, const GError* error = nullptr) {
  g_autofree gchar* remote = error ? g_dbus_error_get_remote_error(error) : nullptr;
  g_print("[LinuxPortal] stage=%s request=%s code=%d error_domain=%s error_code=%d dbus_error=%s\n",
          stage, handle.empty() ? "none" : handle.c_str(), code,
          error ? g_quark_to_string(error->domain) : "none", error ? error->code : 0,
          remote && g_dbus_is_interface_name(remote) ? remote : "none");
}

// Callback and signal owners keep requests alive until all asynchronous work
// finishes, including when a Response arrives before the OpenFile method reply.
struct Request {
  Request(const char* file_path, std::function<void(int, const char*)> callback)
      : path(file_path), complete(std::move(callback)) {}
  ~Request() {
    g_clear_object(&descriptors);
    g_clear_object(&connection);
  }
  std::string path;
  std::function<void(int, const char*)> complete;
  std::string handle;
  GDBusConnection* connection = nullptr;
  GUnixFDList* descriptors = nullptr;
  // Injected short deadlines are used only by the native tests.
  guint response_timeout_ms = 120000;
  guint subscription = 0;
  guint timeout = 0;
  bool finished = false;
};
using Pending = std::shared_ptr<Request>;

void destroy_pending(gpointer data) { delete static_cast<Pending*>(data); }

void finish(const Pending& request, int code, const char* message) {
  if (request->finished) return;
  request->finished = true;
  if (request->subscription != 0) {
    g_dbus_connection_signal_unsubscribe(request->connection,
                                         request->subscription);
    request->subscription = 0;
  }
  if (request->timeout != 0) {
    g_source_remove(request->timeout);
    request->timeout = 0;
  }
  g_clear_object(&request->descriptors);
  request->complete(code, message);
}

void portal_response(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                     const gchar*, GVariant* parameters, gpointer data) {
  Pending request = *static_cast<Pending*>(data);
  if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ua{sv})"))) {
    portal_log("invalid_response_signature", request->handle);
    finish(request, -4, "Invalid portal response signature");
    return;
  }
  guint32 code;
  g_variant_get_child(parameters, 0, "u", &code);
  portal_log("response", request->handle, static_cast<int>(code));
  finish(request, code == 0 ? 0 : -4,
         code == 0 ? "done" : code == 1 ? "Opening cancelled" : "Portal could not open file");
}

gboolean timed_out(gpointer data) {
  Pending request = *static_cast<Pending*>(data);
  request->timeout = 0;
  portal_log("response_timeout", request->handle);
  // Stop a pending chooser rather than reporting failure while it remains open.
  g_dbus_connection_call(request->connection, kDestination,
                         request->handle.c_str(), kRequestInterface, "Close",
                         nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, 5000,
                         nullptr, nullptr, nullptr);
  finish(request, -4, "File opening request timed out");
  return G_SOURCE_REMOVE;
}

void native_launch_finished(GObject*, GAsyncResult* result, gpointer data) {
  std::unique_ptr<Pending> owner(static_cast<Pending*>(data));
  g_autoptr(GError) error = nullptr;
  const gboolean success = g_app_info_launch_default_for_uri_finish(result, &error);
  portal_log("native_launch", (*owner)->handle, success ? 0 : -4, error);
  finish(*owner, success ? 0 : -4, success ? "done" : "Native file open failed");
}

void open_file_finished(GObject* source, GAsyncResult* result, gpointer data) {
  std::unique_ptr<Pending> owner(static_cast<Pending*>(data));
  Pending request = *owner;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_with_unix_fd_list_finish(
      G_DBUS_CONNECTION(source), nullptr, result, &error);
  if (request->finished) return;
  if (reply == nullptr) {
    portal_log("openfile_method_failed", request->handle, -1, error);
    // A desktop without portals can still use its native default application.
    // Never fall back to passing sandbox paths to the host in Flatpak.
    const bool missing_portal =
        g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_SERVICE_UNKNOWN) ||
        g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD);
    if (missing_portal && !in_flatpak()) {
      g_autoptr(GFile) file = g_file_new_for_path(request->path.c_str());
      g_autofree gchar* uri = g_file_get_uri(file);
      g_app_info_launch_default_for_uri_async(uri, nullptr, nullptr,
                                              native_launch_finished,
                                              new Pending(request));
      return;
    }
    finish(request, -4, "Portal OpenFile method failed");
    return;
  }
  const gchar* handle;
  g_variant_get(reply, "(&o)", &handle);
  // Only portal request objects are valid. Avoid logging arbitrary remote paths.
  if (!g_str_has_prefix(handle, "/org/freedesktop/portal/desktop/request/")) {
    portal_log("invalid_request_path", request->handle);
    finish(request, -4, "Invalid portal request path");
    return;
  }
  portal_log("method_reply", handle);
  if (request->handle != handle) {
    // Compatibility with older portals that do not honor handle_token.
    g_dbus_connection_signal_unsubscribe(request->connection, request->subscription);
    request->handle = handle;
    request->subscription = g_dbus_connection_signal_subscribe(
        request->connection, kDestination, kRequestInterface, "Response", handle,
        nullptr, G_DBUS_SIGNAL_FLAGS_NONE, portal_response,
        new Pending(request), destroy_pending);
  }
}

// Flatpak's synthetic home (and /tmp) can contain files that are invisible
// to the host. OpenFile resolves the FD to a host path and verifies its inode;
// it does not turn anonymous/sandbox-only storage into a host file. Stage in
// the app's persistent XDG cache, already bind-mounted by Flatpak. Keep the
// immutable copy after Response: a launched viewer may open it asynchronously.
// One cache entry per source identity/version avoids a new copy on every open.
bool stage_for_portal(const Pending& request, const struct stat& source_stat) {
  g_autofree gchar* identity = g_strdup_printf(
      "%s:%" G_GUINT64_FORMAT ":%" G_GUINT64_FORMAT ":%" G_GINT64_FORMAT
      ":%" G_GINT64_FORMAT ":%ld",
      request->path.c_str(), static_cast<guint64>(source_stat.st_dev),
      static_cast<guint64>(source_stat.st_ino), static_cast<gint64>(source_stat.st_size),
      static_cast<gint64>(source_stat.st_mtim.tv_sec), source_stat.st_mtim.tv_nsec);
  g_autofree gchar* key = g_compute_checksum_for_string(G_CHECKSUM_SHA256, identity, -1);
  g_autofree gchar* directory = g_build_filename(
      g_get_user_cache_dir(), "digitales-register", "portal-open", key, nullptr);
  if (g_mkdir_with_parents(directory, 0700) != 0) {
    portal_log("stage_directory_failed", "", errno);
    return false;
  }
  g_autofree gchar* basename = g_path_get_basename(request->path.c_str());
  g_autofree gchar* destination = g_build_filename(directory, basename, nullptr);
  struct stat cached;
  if (stat(destination, &cached) != 0 || !S_ISREG(cached.st_mode) ||
      cached.st_size != source_stat.st_size) {
    g_autoptr(GFile) source = g_file_new_for_path(request->path.c_str());
    g_autoptr(GFile) target = g_file_new_for_path(destination);
    g_autoptr(GError) error = nullptr;
    if (!g_file_copy(source, target, G_FILE_COPY_OVERWRITE, nullptr, nullptr, nullptr, &error)) {
      portal_log("stage_copy_failed", "", -1, error);
      g_unlink(destination);
      return false;
    }
    portal_log("stage_copy_ready");
  } else {
    portal_log("stage_cache_hit");
  }
  request->path = destination;
  return true;
}

void bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  std::unique_ptr<Pending> owner(static_cast<Pending*>(data));
  Pending request = *owner;
  g_autoptr(GError) error = nullptr;
  request->connection = g_bus_get_finish(result, &error);
  if (request->connection == nullptr) {
    portal_log("session_bus_failed", "", -1, error);
    finish(request, -4, "Session bus unavailable");
    return;
  }
  portal_log("session_bus_ready");
  if (!(g_dbus_connection_get_capabilities(request->connection) &
        G_DBUS_CAPABILITY_FLAGS_UNIX_FD_PASSING)) {
    portal_log("fd_passing_unsupported");
    finish(request, -4, "Session bus does not support Unix FDs");
    return;
  }
  int fd = open(request->path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd == -1) {
    const int saved_errno = errno;
    portal_log("fd_open_failed", "", saved_errno);
    const int code = saved_errno == ENOENT ? -2 : saved_errno == EACCES ? -3 : -4;
    finish(request, code, "Local file descriptor could not be opened");
    return;
  }
  if (in_flatpak()) {
    struct stat source_stat;
    if (fstat(fd, &source_stat) != 0 || !S_ISREG(source_stat.st_mode)) {
      portal_log("source_stat_failed");
      close(fd);
      finish(request, -4, "Expected a regular local file");
      return;
    }
    const bool staged = stage_for_portal(request, source_stat);
    close(fd);
    if (!staged) {
      finish(request, -4, "Portal file staging failed");
      return;
    }
    fd = open(request->path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd == -1) {
      portal_log("staged_fd_open_failed", "", errno);
      finish(request, -4, "Staged file descriptor could not be opened");
      return;
    }
  }
  request->descriptors = g_unix_fd_list_new();
  const int index = g_unix_fd_list_append(request->descriptors, fd, &error);
  // append duplicates fd. The retained list owns that duplicate until finish.
  close(fd);
  if (index == -1) {
    portal_log("fd_append_failed", "", -1, error);
    finish(request, -4, "Could not append Unix FD");
    return;
  }
  portal_log("fd_ready", "", index);
  g_autofree gchar* token = g_uuid_string_random();
  for (gchar* p = token; *p != '\0'; ++p) {
    if (*p == '-') *p = '_';
  }
  std::string sender = g_dbus_connection_get_unique_name(request->connection) + 1;
  for (char& c : sender) {
    if (c == '.') c = '_';
  }
  request->handle = std::string(kPortalPath) + "/request/" + sender + "/" + token;
  // Subscribe before calling OpenFile: a fast portal can respond immediately.
  request->subscription = g_dbus_connection_signal_subscribe(
      request->connection, kDestination, kRequestInterface, "Response",
      request->handle.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      portal_response, new Pending(request), destroy_pending);
  request->timeout = g_timeout_add_full(
      G_PRIORITY_DEFAULT, request->response_timeout_ms, timed_out,
      new Pending(request), destroy_pending);
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string(token));
  g_variant_builder_add(&options, "{sv}", "writable", g_variant_new_boolean(FALSE));
  portal_log("openfile_call", request->handle, index);
  // Empty parent_window is supported on both X11 and Wayland. Pass an FD, not
  // a file:// URI: the portal exports this specific file through Documents.
  g_dbus_connection_call_with_unix_fd_list(
      request->connection, kDestination, kPortalPath,
      "org.freedesktop.portal.OpenURI", "OpenFile",
      g_variant_new("(sha{sv})", "", index, &options), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NONE, 30000, request->descriptors, nullptr,
      open_file_finished, new Pending(request));
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (g_strcmp0(fl_method_call_get_name(call), "open") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* path = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(args, "path") : nullptr;
  if (!path || fl_value_get_type(path) != FL_VALUE_TYPE_STRING ||
      fl_value_get_string(path)[0] == '\0') {
    fl_method_call_respond_error(call, "invalid_path", "File path is required",
                                 nullptr, nullptr);
    return;
  }
  auto retained_call = std::shared_ptr<FlMethodCall>(
      FL_METHOD_CALL(g_object_ref(call)), [](FlMethodCall* value) { g_object_unref(value); });
  Pending request = std::make_shared<Request>(
      fl_value_get_string(path), [retained_call](int code, const char* message) {
        g_autoptr(FlValue) value = fl_value_new_map();
        fl_value_set_string_take(value, "type", fl_value_new_int(code));
        fl_value_set_string_take(value, "message", fl_value_new_string(message));
        g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(value));
        fl_method_call_respond(retained_call.get(), response, nullptr);
      });
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, bus_ready, new Pending(request));
}
}  // namespace

void register_file_open_portal(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "digitales_register/linux_file_open", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call, nullptr, nullptr);
}
