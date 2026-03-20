#include "flutter_window.h"

#include <Windows.h>
#include <gdiplus.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

namespace {

constexpr char kScreenshotChannelName[] =
    "com.creativekoalas.psygo/macos_screenshot";

std::optional<CLSID> GetPngEncoderClsid() {
  UINT num = 0;
  UINT size = 0;
  if (Gdiplus::GetImageEncodersSize(&num, &size) != Gdiplus::Ok || size == 0) {
    return std::nullopt;
  }

  std::vector<BYTE> buffer(size);
  auto* codecs =
      reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  if (Gdiplus::GetImageEncoders(num, size, codecs) != Gdiplus::Ok) {
    return std::nullopt;
  }

  for (UINT i = 0; i < num; ++i) {
    if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
      return codecs[i].Clsid;
    }
  }

  return std::nullopt;
}

std::optional<std::string> Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }

  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0, nullptr, nullptr);
  if (size <= 1) {
    return std::nullopt;
  }

  std::string output(size - 1, '\0');
  if (WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, output.data(), size,
                          nullptr, nullptr) == 0) {
    return std::nullopt;
  }

  return output;
}

}  // namespace

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
  RegisterScreenshotChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  return true;
}

void FlutterWindow::OnDestroy() {
  screenshot_channel_.reset();
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

void FlutterWindow::RegisterScreenshotChannel() {
  screenshot_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kScreenshotChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  screenshot_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "captureScreenBuffer") {
          result->NotImplemented();
          return;
        }

        auto path = CaptureScreenBufferToPng();
        if (!path.has_value()) {
          result->Error("CAPTURE_FAILED",
                        "Failed to capture the current screen buffer.");
          return;
        }

        auto path_utf8 = Utf8FromWide(path.value());
        if (!path_utf8.has_value()) {
          result->Error("CAPTURE_FAILED",
                        "Failed to encode the screenshot file path.");
          return;
        }

        result->Success(flutter::EncodableValue(path_utf8.value()));
      });
}

std::optional<std::wstring> FlutterWindow::CaptureScreenBufferToPng() const {
  const int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (width <= 0 || height <= 0) {
    return std::nullopt;
  }

  HDC screen_dc = GetDC(nullptr);
  if (!screen_dc) {
    return std::nullopt;
  }

  HDC memory_dc = CreateCompatibleDC(screen_dc);
  if (!memory_dc) {
    ReleaseDC(nullptr, screen_dc);
    return std::nullopt;
  }

  HBITMAP bitmap = CreateCompatibleBitmap(screen_dc, width, height);
  if (!bitmap) {
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return std::nullopt;
  }

  HGDIOBJ old_object = SelectObject(memory_dc, bitmap);
  const bool copied =
      BitBlt(memory_dc, 0, 0, width, height, screen_dc, x, y, SRCCOPY |
      CAPTUREBLT);
  SelectObject(memory_dc, old_object);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  if (!copied) {
    DeleteObject(bitmap);
    return std::nullopt;
  }

  WCHAR temp_path[MAX_PATH];
  DWORD temp_length = GetTempPathW(MAX_PATH, temp_path);
  if (temp_length == 0 || temp_length > MAX_PATH) {
    DeleteObject(bitmap);
    return std::nullopt;
  }

  WCHAR temp_file[MAX_PATH];
  if (GetTempFileNameW(temp_path, L"psy", 0, temp_file) == 0) {
    DeleteObject(bitmap);
    return std::nullopt;
  }
  DeleteFileW(temp_file);

  std::wstring output_path(temp_file);
  output_path += L".png";
  DeleteFileW(output_path.c_str());

  Gdiplus::GdiplusStartupInput startup_input;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &startup_input, nullptr) !=
      Gdiplus::Ok) {
    DeleteObject(bitmap);
    return std::nullopt;
  }

  std::optional<CLSID> png_encoder = GetPngEncoderClsid();
  if (!png_encoder.has_value()) {
    Gdiplus::GdiplusShutdown(token);
    DeleteObject(bitmap);
    return std::nullopt;
  }

  Gdiplus::Bitmap image(bitmap, nullptr);
  const auto save_status = image.Save(output_path.c_str(), &png_encoder.value(),
                                      nullptr);

  Gdiplus::GdiplusShutdown(token);
  DeleteObject(bitmap);

  if (save_status != Gdiplus::Ok) {
    DeleteFileW(output_path.c_str());
    return std::nullopt;
  }

  return output_path;
}
