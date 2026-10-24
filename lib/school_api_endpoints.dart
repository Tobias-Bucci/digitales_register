/// Existing school API contract, shared by UI and headless clients.
/// No provider-specific endpoints or additional backend are assumed.
String schoolApiBase(String server) =>
    '${server.replaceAll(RegExp(r'/+$'), '')}/v2/';
const schoolLoginEndpoint = 'api/auth/login';
const schoolUnreadNotificationsEndpoint = 'api/notification/unread';
