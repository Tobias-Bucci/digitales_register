// Run with tool/test_linux_file_open.sh under Linux and an installed Flutter SDK.
// Include the implementation to exercise its asynchronous request handling
// against a private D-Bus portal without launching host applications.
#include "../file_open_portal.cc"

namespace {
GDBusConnection* service;
guint response_code;
bool reject_call;
bool received_fd;
bool received_read_only;
bool response_before_reply;

void mock_open(GDBusConnection* connection, const gchar* sender, const gchar*,
               const gchar*, const gchar*, GVariant* parameters,
               GDBusMethodInvocation* invocation, gpointer) {
  if (reject_call) {
    g_dbus_method_invocation_return_dbus_error(
        invocation, "org.freedesktop.portal.Error.Failed", "Mock launch failed");
    return;
  }
  const gchar* parent;
  gint32 index;
  g_autoptr(GVariant) options = nullptr;
  g_variant_get(parameters, "(&sh@a{sv})", &parent, &index, &options);
  g_assert_cmpstr(parent, ==, "");
  GUnixFDList* list = g_dbus_message_get_unix_fd_list(
      g_dbus_method_invocation_get_message(invocation));
  g_assert_nonnull(list);
  const int fd = g_unix_fd_list_get(list, index, nullptr);
  g_assert_cmpint(fd, >=, 0);
  char buffer[32] = {};
  g_assert_cmpint(read(fd, buffer, sizeof(buffer) - 1), ==, 14);
  g_assert_cmpstr(buffer, ==, "portal payload");
  received_fd = true;
  received_read_only = (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY;
  close(fd);
  const gchar* token;
  gboolean writable = TRUE;
  g_assert_true(g_variant_lookup(options, "handle_token", "&s", &token));
  g_assert_true(g_variant_lookup(options, "writable", "b", &writable));
  g_assert_false(writable);
  std::string requester = sender + 1;
  for (char& c : requester) if (c == '.') c = '_';
  const std::string handle = std::string(kPortalPath) + "/request/" + requester + "/" + token;
  auto emit_response = [&]() {
    GVariantBuilder results;
    g_variant_builder_init(&results, G_VARIANT_TYPE_VARDICT);
    g_dbus_connection_emit_signal(
        connection, sender, handle.c_str(), kRequestInterface, "Response",
        g_variant_new("(ua{sv})", response_code, &results), nullptr);
  };
  if (response_before_reply) emit_response();
  g_dbus_method_invocation_return_value(invocation, g_variant_new("(o)", handle.c_str()));
  if (!response_before_reply) emit_response();
}

void exercise(const char* path, guint code, int expected,
              bool failure = false, bool early = false) {
  response_code = code;
  reject_call = failure;
  response_before_reply = early;
  received_fd = false;
  bool completed = false;
  int actual = 99;
  int completions = 0;
  Pending request = std::make_shared<Request>(path, [&](int result, const char* message) {
    actual = result;
    g_assert_nonnull(message);
    ++completions;
    completed = true;
  });
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
  if (!failure && expected != -2) {
    g_assert_true(received_fd);
    g_assert_true(received_read_only);
  }
}
}  // namespace

int main() {
  g_setenv("FLATPAK_ID", "io.github.tobias_bucci.digitales_register", TRUE);
  g_autoptr(GError) error = nullptr;
  service = g_dbus_connection_new_for_address_sync(
      g_getenv("DBUS_SESSION_BUS_ADDRESS"),
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                        G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  g_assert_no_error(error);
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
  exercise(path, 0, 0);
  exercise(path, 0, 0, false, true);
  exercise(path, 1, -4);
  exercise(path, 2, -4);
  exercise(path, 0, -4, true);
  g_assert_cmpint(unlink(path), ==, 0);
  exercise(path, 0, -2);
  g_assert_cmpint(rmdir(directory), ==, 0);
  g_dbus_connection_unregister_object(service, registration);
  g_object_unref(service);
  g_print("PASS: FD transfer, read-only access, early response, cancellation, portal failure, missing file\n");
  return 0;
}
