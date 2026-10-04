#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  flutter::MethodChannel<flutter::EncodableValue> file_channel(
      flutter_controller_->engine()->messenger(),
      "digitales_register/windows_file_open",
      &flutter::StandardMethodCodec::GetInstance());
  file_channel.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "open") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const std::string* path = nullptr;
        if (args != nullptr) {
          const auto it = args->find(flutter::EncodableValue("path"));
          if (it != args->end()) path = std::get_if<std::string>(&it->second);
        }
        if (path == nullptr || path->empty() || path->find('\0') != std::string::npos) {
          result->Error("invalid_path", "Expected a local file path");
          return;
        }
        const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            path->c_str(), -1, nullptr, 0);
        if (size == 0) {
          result->Error("invalid_path", "Invalid UTF-8 path");
          return;
        }
        std::wstring wide_path(size, L'\0');
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(), -1,
                            wide_path.data(), size);
        const DWORD attributes = GetFileAttributesW(wide_path.c_str());
        int code = -2;
        if (attributes != INVALID_FILE_ATTRIBUTES &&
            !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
          const auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(
              GetHandle(), L"open", wide_path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
          code = status > 32 ? 0 : status == SE_ERR_NOASSOC ? -1 :
                 status == SE_ERR_ACCESSDENIED ? -3 : -4;
        }
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("type"), flutter::EncodableValue(code)},
            {flutter::EncodableValue("message"),
             flutter::EncodableValue(code == 0 ? "done" : "Windows shell could not open file")}}));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
