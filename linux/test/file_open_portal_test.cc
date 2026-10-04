// Run with tool/test_linux_file_open.sh under Linux and an installed Flutter SDK.
// Include the implementation to exercise its asynchronous request handling
// against a private D-Bus portal without launching host applications.
#include "../file_open_portal.cc"
#include <cstdio>

namespace {
GDBusConnection* service;
guint response_code;
bool reject_call;
bool received_fd;
bool received_read_only;
bool response_before_reply;
bool suppress_response;
bool malformed_response;
bool alternate_handle;
bool service_unknown;
bool received_close;
std::string cache_root;
std::string source_path;
std::string last_received_path;
std::string last_message;
std::string captured_logs;

void mock_close(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                const gchar*, GVariant*, GDBusMethodInvocation* invocation, gpointer) {
  received_close = true;
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

const GDBusInterfaceVTable close_vtable = {mock_close, nullptr, nullptr, {nullptr}};
GDBusInterfaceInfo* close_info;
guint close_registration;

void mock_open(GDBusConnection* connection, const gchar* sender, const gchar*,
               const gchar*, const gchar*, GVariant* parameters,
               GDBusMethodInvocation* invocation, gpointer) {
  if (reject_call) {
    g_dbus_method_invocation_return_dbus_error(
        invocation, service_unknown ? "org.freedesktop.DBus.Error.ServiceUnknown"
                                    : "org.freedesktop.portal.Error.Failed",
        "SECRET_BACKEND_DATA must not be logged");
    return;
  }
  g_assert_true(g_variant_is_of_type(parameters, G_VARIANT_TYPE("(sha{sv})")));
  const gchar* parent;
  gint32 index;
  g_autoptr(GVariant) options = nullptr;
  g_variant_get(parameters, "(&sh@a{sv})", &parent, &index, &options);
  g_assert_cmpstr(parent, ==, "");
  GUnixFDList* list = g_dbus_message_get_unix_fd_list(
      g_dbus_method_invocation_get_message(invocation));
  g_assert_nonnull(list);
  g_assert_cmpint(index, ==, 0);
  g_assert_cmpint(g_unix_fd_list_get_length(list), ==, 1);
  const int fd = g_unix_fd_list_get(list, index, nullptr);
  g_assert_cmpint(fd, >=, 0);
  char buffer[32] = {};
  g_assert_cmpint(read(fd, buffer, sizeof(buffer) - 1), ==, 14);
  g_assert_cmpstr(buffer, ==, "portal payload");
  received_fd = true;
  received_read_only = (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY;
  const std::string proc = "/proc/self/fd/" + std::to_string(fd);
  g_autofree gchar* transferred_path = g_file_read_link(proc.c_str(), nullptr);
  g_assert_nonnull(transferred_path);
  last_received_path = transferred_path;
  if (in_flatpak()) {
    // Emulate the portal's host-path/inode verification: the staged file must
    // be persistent cache storage, not the synthetic-home input path.
    g_assert_true(g_str_has_prefix(transferred_path, cache_root.c_str()));
    g_assert_cmpstr(transferred_path, !=, source_path.c_str());
    g_autofree gchar* original_basename = g_path_get_basename(source_path.c_str());
    g_autofree gchar* staged_basename = g_path_get_basename(transferred_path);
    g_assert_cmpstr(original_basename, ==, staged_basename);
  } else {
    g_assert_cmpstr(transferred_path, ==, source_path.c_str());
  }
  struct stat fd_stat, host_stat;
  g_assert_cmpint(fstat(fd, &fd_stat), ==, 0);
  g_assert_cmpint(stat(transferred_path, &host_stat), ==, 0);
  g_assert_cmpuint(fd_stat.st_ino, ==, host_stat.st_ino);
  g_assert_cmpuint(fd_stat.st_dev, ==, host_stat.st_dev);
  close(fd);
  const gchar* token;
  gboolean writable = TRUE;
  g_assert_true(g_variant_lookup(options, "handle_token", "&s", &token));
  g_assert_true(g_variant_lookup(options, "writable", "b", &writable));
  g_assert_false(writable);
  std::string requester = sender + 1;
  for (char& c : requester) if (c == '.') c = '_';
  const std::string handle = std::string(kPortalPath) + "/request/" + requester + "/" +
                            (alternate_handle ? "legacy_handle" : token);
  if (suppress_response) {
    close_registration = g_dbus_connection_register_object(
        connection, handle.c_str(), close_info, &close_vtable, nullptr, nullptr, nullptr);
    g_assert_cmpuint(close_registration, !=, 0);
  }
  auto emit_response = [&]() {
    GVariantBuilder results;
    g_variant_builder_init(&results, G_VARIANT_TYPE_VARDICT);
    g_dbus_connection_emit_signal(
        connection, sender, handle.c_str(), kRequestInterface, "Response",
        malformed_response ? g_variant_new("(s)", "SECRET_RESULTS")
                           : g_variant_new("(ua{sv})", response_code, &results), nullptr);
  };
  if (response_before_reply) emit_response();
  g_dbus_method_invocation_return_value(invocation, g_variant_new("(o)", handle.c_str()));
  if (!response_before_reply && !suppress_response) {
    if (alternate_handle) {
      // Old portals return an unpredictable handle. Deliver after subscription
      // adjustment, as the normal asynchronous user interaction does.
      struct Signal { std::string sender; std::string handle; };
      auto* signal = new Signal{sender, handle};
      g_timeout_add(30, [](gpointer data) -> gboolean {
        std::unique_ptr<Signal> signal(static_cast<Signal*>(data));
        GVariantBuilder results;
        g_variant_builder_init(&results, G_VARIANT_TYPE_VARDICT);
        g_dbus_connection_emit_signal(service, signal->sender.c_str(), signal->handle.c_str(),
            kRequestInterface, "Response", g_variant_new("(ua{sv})", response_code, &results), nullptr);
        return G_SOURCE_REMOVE;
      }, signal);
    } else {
      emit_response();
    }
  }
}

void exercise(const char* path, guint code, int expected,
              bool failure = false, bool early = false) {
  response_code = code;
  reject_call = failure;
  response_before_reply = early;
  received_fd = false;
  received_close = false;
  bool completed = false;
  int actual = 99;
  int completions = 0;
  Pending request = std::make_shared<Request>(path, [&](int result, const char* message) {
    actual = result;
    g_assert_nonnull(message);
    last_message = message;
    ++completions;
    completed = true;
  });
  if (suppress_response) request->response_timeout_ms = 50;
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, bus_ready, new Pending(request));
  const gint64 deadline = g_get_monotonic_time() + 5 * G_TIME_SPAN_SECOND;
  while (!completed && g_get_monotonic_time() < deadline) {
    g_main_context_iteration(nullptr, FALSE);
    g_usleep(1000);
  }
  g_assert_true(completed);
  // Drain method reply callbacks after an early Response as well.
  for (int i = 0; i < 100; ++i) {
    g_main_context_iteration(nullptr, FALSE);
    g_usleep(1000);
  }
  g_assert_cmpint(actual, ==, expected);
  g_assert_cmpint(completions, ==, 1);
  g_assert_cmpuint(request->subscription, ==, 0);
  g_assert_cmpuint(request->timeout, ==, 0);
  g_assert_null(request->descriptors);
  if (suppress_response) {
    g_assert_true(received_close);
    g_assert_cmpstr(last_message.c_str(), ==, "File opening request timed out");
    g_dbus_connection_unregister_object(service, close_registration);
  }
  if (!failure && expected != -2) {
    g_assert_true(received_fd);
    g_assert_true(received_read_only);
  }
}
}  // namespace

int main() {
  g_set_print_handler([](const gchar* message) {
    captured_logs += message;
    std::fputs(message, stdout);
  });
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* test_cache = g_dir_make_tmp("portal-cache-XXXXXX", &error);
  g_assert_no_error(error);
  cache_root = test_cache;
  g_setenv("XDG_CACHE_HOME", test_cache, TRUE);
  g_setenv("FLATPAK_ID", "io.github.tobias_bucci.digitales_register", TRUE);
  service = g_dbus_connection_new_for_address_sync(
      g_getenv("DBUS_SESSION_BUS_ADDRESS"),
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                        G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  g_assert_no_error(error);
  g_autoptr(GDBusNodeInfo) close_node = g_dbus_node_info_new_for_xml(
      "<node><interface name='org.freedesktop.portal.Request'>"
      "<method name='Close'/></interface></node>", &error);
  g_assert_no_error(error);
  close_info = close_node->interfaces[0];
  g_autoptr(GVariant) owned = g_dbus_connection_call_sync(
      service, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "RequestName", g_variant_new("(su)", kDestination, 0),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &error);
  g_assert_no_error(error);
  g_autoptr(GDBusNodeInfo) info = g_dbus_node_info_new_for_xml(
      "<node><interface name='org.freedesktop.portal.OpenURI'>"
      "<method name='OpenFile'><arg type='s' direction='in'/>"
      "<arg type='h' direction='in'/><arg type='a{sv}' direction='in'/>"
      "<arg type='o' direction='out'/></method></interface></node>", &error);
  g_assert_no_error(error);
  const GDBusInterfaceVTable vtable = {mock_open, nullptr, nullptr, {nullptr}};
  const guint registration = g_dbus_connection_register_object(
      service, kPortalPath, info->interfaces[0], &vtable, nullptr, nullptr, &error);
  g_assert_no_error(error);
  g_autofree gchar* directory = g_dir_make_tmp("file-open-XXXXXX", &error);
  g_assert_no_error(error);
  g_autofree gchar* path = g_build_filename(directory, "Prüfung mit Leerzeichen #1.txt", nullptr);
  g_assert_true(g_file_set_contents(path, "portal payload", -1, &error));
  source_path = path;
  exercise(path, 0, 0);
  const std::string first_cache_path = last_received_path;
  exercise(path, 0, 0, false, true);
  g_assert_cmpstr(last_received_path.c_str(), ==, first_cache_path.c_str());
  // The staged pathname remains usable after completion and FD cleanup.
  g_assert_true(g_file_test(first_cache_path.c_str(), G_FILE_TEST_IS_REGULAR));
  exercise(path, 1, -4);
  exercise(path, 2, -4);
  exercise(path, 0, -4, true);
  service_unknown = true;
  exercise(path, 0, -4, true);
  service_unknown = false;
  g_assert_cmpstr(last_message.c_str(), ==, "Portal OpenFile method failed");
  suppress_response = true;
  exercise(path, 0, -4);
  suppress_response = false;
  malformed_response = true;
  exercise(path, 0, -4);
  malformed_response = false;
  g_assert_cmpstr(last_message.c_str(), ==, "Invalid portal response signature");
  alternate_handle = true;
  exercise(path, 0, 0);
  alternate_handle = false;
  g_unsetenv("FLATPAK_ID");
  exercise(path, 0, 0);
  g_setenv("FLATPAK_ID", "io.github.tobias_bucci.digitales_register", TRUE);
  g_assert_cmpint(unlink(path), ==, 0);
  exercise(path, 0, -2);
  g_assert_null(strstr(captured_logs.c_str(), "SECRET_"));
  g_assert_null(strstr(captured_logs.c_str(), source_path.c_str()));
  g_assert_null(strstr(captured_logs.c_str(), cache_root.c_str()));
  g_assert_nonnull(strstr(captured_logs.c_str(), "stage=response_timeout"));
  g_assert_nonnull(strstr(captured_logs.c_str(), "dbus_error=org.freedesktop.portal.Error.Failed"));
  g_assert_nonnull(strstr(captured_logs.c_str(), "stage=response"));
  g_assert_cmpint(rmdir(directory), ==, 0);
  g_dbus_connection_unregister_object(service, registration);
  g_object_unref(service);
  // Remove only the isolated test cache, never the user's real app cache.
  // All staged files share this source identity, so this test creates one leaf.
  g_assert_cmpint(g_unlink(first_cache_path.c_str()), ==, 0);
  g_autofree gchar* leaf = g_path_get_dirname(first_cache_path.c_str());
  g_assert_cmpint(g_rmdir(leaf), ==, 0);
  g_autofree gchar* portal_dir = g_path_get_dirname(leaf);
  g_assert_cmpint(g_rmdir(portal_dir), ==, 0);
  g_autofree gchar* app_dir = g_path_get_dirname(portal_dir);
  g_assert_cmpint(g_rmdir(app_dir), ==, 0);
  g_assert_cmpint(g_rmdir(test_cache), ==, 0);
  g_print("PASS: signature, cache staging/reuse, FD lifetime/inode/read-only, spaces/umlauts, success, early/legacy response, cancel, response error, D-Bus error/service unavailable, timeout/Close, malformed response, missing file, native path\n");
  return 0;
}
