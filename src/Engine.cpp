#include "jave/Engine.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <mmsystem.h>
#include <sstream>
#include <stdexcept>

namespace jave {
namespace {

constexpr wchar_t WindowClass[] = L"JaveEngineWindow";
COLORREF mixColor(COLORREF a, COLORREF b, double amount) {
    amount = std::clamp(amount, 0.0, 1.0);
    const auto channel = [amount](int x, int y) { return static_cast<int>(x + (y - x) * amount); };
    return RGB(channel(GetRValue(a), GetRValue(b)), channel(GetGValue(a), GetGValue(b)), channel(GetBValue(a), GetBValue(b)));
}

std::wstring keyName(int key) {
    UINT scan = MapVirtualKeyW(static_cast<UINT>(key), MAPVK_VK_TO_VSC) << 16;
    if (key == VK_LEFT || key == VK_UP || key == VK_RIGHT || key == VK_DOWN || key == VK_INSERT ||
        key == VK_DELETE || key == VK_HOME || key == VK_END || key == VK_PRIOR || key == VK_NEXT) scan |= 1u << 24;
    wchar_t buffer[64]{};
    if (GetKeyNameTextW(static_cast<LONG>(scan), buffer, 64) > 0) return buffer;
    return L"Key " + std::to_wstring(key);
}

std::wstring percent(double value) {
    return std::to_wstring(static_cast<int>(std::round(value * 100.0))) + L"%";
}

double chartSnapMs(const Chart& chart) {
    return 60000.0 / std::clamp(chart.bpm, 1.0, 1000.0) / 4.0;
}

struct ChartEditorLayout {
    float gridX{};
    float gridY{};
    float gridWidth{};
    float gridHeight{};
    float laneWidth{};
    float panelX{};
    float panelWidth{};
    float actionsY{};
};

ChartEditorLayout chartEditorLayout(int width, int height) {
    ChartEditorLayout layout;
    layout.gridX = 58.0f;
    layout.gridY = 205.0f;
    layout.gridWidth = std::max(480.0f, static_cast<float>(width) - 520.0f);
    layout.gridHeight = std::max(300.0f, static_cast<float>(height) - 315.0f);
    layout.laneWidth = layout.gridWidth / 8.0f;
    layout.panelX = layout.gridX + layout.gridWidth + 28.0f;
    layout.panelWidth = static_cast<float>(width) - layout.panelX - 48.0f;
    layout.actionsY = layout.gridY + 105.0f;
    return layout;
}

bool pointInBox(const POINT& point, float x, float y, float width, float height) {
    return point.x >= x && point.x < x + width && point.y >= y && point.y < y + height;
}

const wchar_t* poseName(int pose) {
    if (pose == 4) return L"danceRight";
    constexpr const wchar_t* names[] = {L"left", L"down", L"up", L"right"};
    return pose >= 0 && pose < 4 ? names[pose] : L"idle";
}

const Json& characterMetadata(const std::filesystem::path& base) {
    static std::map<std::wstring, Json> cache;
    const auto key = base.wstring();
    auto found = cache.find(key);
    if (found == cache.end()) {
        Json metadata(Json::Object{});
        try { metadata = Json::fromFile(base / "animation.json"); } catch (...) {}
        found = cache.emplace(key, std::move(metadata)).first;
    }
    return found->second;
}

std::filesystem::path animatedPosePath(const std::filesystem::path& base, int pose, double animationTime) {
    const std::filesystem::path directory = base / poseName(pose);
    static std::map<std::wstring, std::vector<std::filesystem::path>> frameCache;
    const std::wstring key = directory.wstring();
    auto found = frameCache.find(key);
    if (found == frameCache.end()) {
        std::vector<std::filesystem::path> frames;
        if (std::filesystem::is_directory(directory)) {
            for (const auto& entry : std::filesystem::directory_iterator(directory)) {
                if (entry.is_regular_file() && entry.path().extension() == L".png" &&
                    entry.path().filename().wstring().starts_with(L"frame_")) frames.push_back(entry.path());
            }
            std::sort(frames.begin(), frames.end());
        }
        found = frameCache.emplace(key, std::move(frames)).first;
    }
    if (found->second.empty()) return base / (std::wstring(poseName(pose)) + L".png");
    const Json& animation = characterMetadata(base)[pose < 0 ? "idle" :
        pose == 0 ? "left" : pose == 1 ? "down" : pose == 2 ? "up" : pose == 4 ? "danceRight" : "right"];
    const double fps = std::clamp(animation["fps"].asNumber(24.0), 1.0, 120.0);
    const std::size_t frame = static_cast<std::size_t>(std::max(0.0, animationTime) * fps);
    const std::size_t index = animation["loop"].asBool(pose < 0)
        ? frame % found->second.size() : std::min(frame, found->second.size() - 1);
    return found->second[index];
}

std::filesystem::path noteImagePath(const std::filesystem::path& root, const wchar_t* kind, int lane) {
    constexpr const wchar_t* lanes[] = {L"left", L"down", L"up", L"right"};
    static std::map<std::wstring, std::filesystem::path> resolved;
    const std::wstring fileName = std::wstring(kind) + L"_" + lanes[std::clamp(lane, 0, 3)] + L".png";
    const std::filesystem::path imported = root / "assets" / "imported" / "notes" / fileName;
    const auto found = resolved.find(imported.wstring());
    if (found != resolved.end()) return found->second;
    std::error_code error;
    const std::filesystem::path path =
        std::filesystem::exists(imported, error) ? imported : root / "assets" / "demo" / "notes" / fileName;
    resolved.emplace(imported.wstring(), path);
    return path;
}

} // namespace

std::wstring widen(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return std::wstring(value.begin(), value.end());
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), length);
    return result;
}

void InputState::onKeyDown(unsigned key) {
    if (key >= down.size()) return;
    if (!down[key]) pressed[key] = true;
    down[key] = true;
}
void InputState::onKeyUp(unsigned key) { if (key < down.size()) down[key] = false; }
void InputState::endFrame() { pressed.fill(false); }
bool InputState::wasPressed(int key) const { return key >= 0 && key < static_cast<int>(pressed.size()) && pressed[static_cast<std::size_t>(key)]; }

Renderer::Renderer() {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&gdiplusToken_, &input, nullptr);
}
Renderer::~Renderer() {
    graphics_.reset();
    images_.clear();
    for (const auto& [key, font] : fonts_) {
        (void)key;
        if (font) DeleteObject(font);
    }
    fonts_.clear();
    if (memory_ && oldBitmap_) SelectObject(memory_, oldBitmap_);
    if (bitmap_) DeleteObject(bitmap_);
    if (memory_) DeleteDC(memory_);
    if (gdiplusToken_) Gdiplus::GdiplusShutdown(gdiplusToken_);
}

void Renderer::resize(HWND window, int width, int height) {
    width = std::max(width, 1);
    height = std::max(height, 1);
    if (width == width_ && height == height_ && memory_) return;
    HDC target = GetDC(window);
    if (!memory_) memory_ = CreateCompatibleDC(target);
    if (bitmap_) {
        SelectObject(memory_, oldBitmap_);
        DeleteObject(bitmap_);
    }
    bitmap_ = CreateCompatibleBitmap(target, width, height);
    oldBitmap_ = static_cast<HBITMAP>(SelectObject(memory_, bitmap_));
    ReleaseDC(window, target);
    width_ = width;
    height_ = height;
    SetBkMode(memory_, TRANSPARENT);
}

void Renderer::begin(HDC, int width, int height) {
    width_ = width;
    height_ = height;
    graphics_.reset();
}
RenderViewport RenderViewport::fit(int width, int height) {
    width = std::max(width, 1); height = std::max(height, 1);
    const double scale = std::min(width / double(CanvasWidth), height / double(CanvasHeight));
    const int fittedWidth = std::max(1, static_cast<int>(std::round(CanvasWidth * scale)));
    const int fittedHeight = std::max(1, static_cast<int>(std::round(CanvasHeight * scale)));
    return {(width - fittedWidth) / 2, (height - fittedHeight) / 2, fittedWidth, fittedHeight};
}

POINT RenderViewport::toCanvas(POINT point) const {
    if (point.x < x || point.y < y || point.x >= x + width || point.y >= y + height)
        return {-1, -1}; // Letterbox bars are not clickable game content.
    return {static_cast<LONG>((point.x - x) * double(CanvasWidth) / width),
            static_cast<LONG>((point.y - y) * double(CanvasHeight) / height)};
}

void Renderer::end(HDC target, int outputWidth, int outputHeight) {
    graphics_.reset();
    if (outputWidth <= 0 || outputHeight <= 0) {
        BitBlt(target, 0, 0, width_, height_, memory_, 0, 0, SRCCOPY);
        return;
    }
    const auto viewport = RenderViewport::fit(outputWidth, outputHeight);
    // Only clear the bars, not the entire output image a second time.
    const auto black = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    RECT bars[] = {{0, 0, outputWidth, viewport.y},
                   {0, viewport.y + viewport.height, outputWidth, outputHeight},
                   {0, viewport.y, viewport.x, viewport.y + viewport.height},
                   {viewport.x + viewport.width, viewport.y, outputWidth, viewport.y + viewport.height}};
    for (const auto& bar : bars) if (bar.right > bar.left && bar.bottom > bar.top) FillRect(target, &bar, black);
    if (viewport.width == width_ && viewport.height == height_)
        BitBlt(target, viewport.x, viewport.y, width_, height_, memory_, 0, 0, SRCCOPY);
    else {
        const int oldMode = SetStretchBltMode(target, HALFTONE);
        POINT oldOrigin{};
        SetBrushOrgEx(target, 0, 0, &oldOrigin);
        StretchBlt(target, viewport.x, viewport.y, viewport.width, viewport.height,
                   memory_, 0, 0, width_, height_, SRCCOPY);
        SetBrushOrgEx(target, oldOrigin.x, oldOrigin.y, nullptr);
        SetStretchBltMode(target, oldMode);
    }
}

void Renderer::clearGradient(COLORREF top, COLORREF bottom) {
    graphics_.reset();
    TRIVERTEX vertices[2] = {
        {0, 0, static_cast<COLOR16>(GetRValue(top) << 8), static_cast<COLOR16>(GetGValue(top) << 8), static_cast<COLOR16>(GetBValue(top) << 8), 0xFF00},
        {width_, height_, static_cast<COLOR16>(GetRValue(bottom) << 8), static_cast<COLOR16>(GetGValue(bottom) << 8), static_cast<COLOR16>(GetBValue(bottom) << 8), 0xFF00}
    };
    GRADIENT_RECT rectangle{0, 1};
    GradientFill(memory_, vertices, 2, &rectangle, 1, GRADIENT_FILL_RECT_V);
}

void Renderer::rect(float x, float y, float w, float h, COLORREF color, int radius) {
    graphics_.reset();
    HBRUSH brush = CreateSolidBrush(color);
    HGDIOBJ oldBrush = SelectObject(memory_, brush);
    HGDIOBJ oldPen = SelectObject(memory_, GetStockObject(NULL_PEN));
    if (radius > 0) RoundRect(memory_, static_cast<int>(x), static_cast<int>(y), static_cast<int>(x + w), static_cast<int>(y + h), radius, radius);
    else Rectangle(memory_, static_cast<int>(x), static_cast<int>(y), static_cast<int>(x + w), static_cast<int>(y + h));
    SelectObject(memory_, oldPen);
    SelectObject(memory_, oldBrush);
    DeleteObject(brush);
}

void Renderer::outline(float x, float y, float w, float h, COLORREF color, int thickness, int radius) {
    graphics_.reset();
    HPEN pen = CreatePen(PS_SOLID, thickness, color);
    HGDIOBJ oldPen = SelectObject(memory_, pen);
    HGDIOBJ oldBrush = SelectObject(memory_, GetStockObject(HOLLOW_BRUSH));
    if (radius > 0) RoundRect(memory_, static_cast<int>(x), static_cast<int>(y), static_cast<int>(x + w), static_cast<int>(y + h), radius, radius);
    else Rectangle(memory_, static_cast<int>(x), static_cast<int>(y), static_cast<int>(x + w), static_cast<int>(y + h));
    SelectObject(memory_, oldBrush);
    SelectObject(memory_, oldPen);
    DeleteObject(pen);
}

void Renderer::text(const std::wstring& value, float x, float y, float w, float h, int size, COLORREF color, UINT align, bool bold) {
    graphics_.reset();
    const auto fontKey = std::make_pair(size, bold);
    auto fontEntry = fonts_.find(fontKey);
    if (fontEntry == fonts_.end()) {
        HFONT created = CreateFontW(-size, 0, 0, 0, bold ? FW_BOLD : FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                   OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
        fontEntry = fonts_.emplace(fontKey, created).first;
    }
    HFONT font = fontEntry->second;
    HGDIOBJ oldFont = SelectObject(memory_, font);
    SetTextColor(memory_, color);
    RECT area{static_cast<LONG>(x), static_cast<LONG>(y), static_cast<LONG>(x + w), static_cast<LONG>(y + h)};
    DrawTextW(memory_, value.c_str(), static_cast<int>(value.size()), &area, align);
    SelectObject(memory_, oldFont);
}

void Renderer::ellipse(float x, float y, float w, float h, COLORREF color) {
    graphics_.reset();
    HBRUSH brush = CreateSolidBrush(color);
    HGDIOBJ oldBrush = SelectObject(memory_, brush);
    HGDIOBJ oldPen = SelectObject(memory_, GetStockObject(NULL_PEN));
    Ellipse(memory_, static_cast<int>(x), static_cast<int>(y), static_cast<int>(x + w), static_cast<int>(y + h));
    SelectObject(memory_, oldPen);
    SelectObject(memory_, oldBrush);
    DeleteObject(brush);
}

void Renderer::polygon(const std::vector<POINT>& points, COLORREF fill, COLORREF border, int thickness) {
    graphics_.reset();
    if (points.size() < 3) return;
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, thickness, border);
    HGDIOBJ oldBrush = SelectObject(memory_, brush);
    HGDIOBJ oldPen = SelectObject(memory_, pen);
    Polygon(memory_, points.data(), static_cast<int>(points.size()));
    SelectObject(memory_, oldPen);
    SelectObject(memory_, oldBrush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void Renderer::image(const std::filesystem::path& path, float x, float y, float w, float h, bool flipX, bool stretch) {
    if (path.empty() || w <= 0 || h <= 0) return;
    const std::wstring key = path.wstring();
    auto found = images_.find(key);
    if (found == images_.end()) {
        if (!std::filesystem::is_regular_file(path)) return;
        auto loaded = std::make_unique<Gdiplus::Image>(key.c_str());
        if (loaded->GetLastStatus() != Gdiplus::Ok) return;
        found = images_.emplace(key, std::move(loaded)).first;
    }
    Gdiplus::Image& bitmap = *found->second;
    const float sourceW = static_cast<float>(bitmap.GetWidth());
    const float sourceH = static_cast<float>(bitmap.GetHeight());
    if (sourceW <= 0 || sourceH <= 0) return;
    const float scale = std::min(w / sourceW, h / sourceH);
    const float drawW = stretch ? w : sourceW * scale;
    const float drawH = stretch ? h : sourceH * scale;
    const float drawX = x + (w - drawW) * 0.5f;
    const float drawY = y + h - drawH;
    if (!graphics_) {
        graphics_ = std::make_unique<Gdiplus::Graphics>(memory_);
        graphics_->SetCompositingMode(Gdiplus::CompositingModeSourceOver);
        graphics_->SetCompositingQuality(Gdiplus::CompositingQualityHighSpeed);
        graphics_->SetInterpolationMode(Gdiplus::InterpolationModeBilinear);
        graphics_->SetSmoothingMode(Gdiplus::SmoothingModeHighSpeed);
        graphics_->SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    }
    if (flipX) {
        Gdiplus::PointF points[] = {{drawX + drawW, drawY}, {drawX, drawY}, {drawX + drawW, drawY + drawH}};
        graphics_->DrawImage(&bitmap, points, 3, 0, 0, sourceW, sourceH, Gdiplus::UnitPixel);
    } else {
        graphics_->DrawImage(&bitmap, Gdiplus::RectF(drawX, drawY, drawW, drawH));
    }
}

Engine::Engine(HINSTANCE instance, std::filesystem::path dataRoot)
    : instance_(instance), content_([&] {
        if (!dataRoot.empty()) return dataRoot;
        wchar_t path[MAX_PATH]{};
        GetModuleFileNameW(nullptr, path, MAX_PATH);
        return std::filesystem::path(path).parent_path();
      }()) {
    root_ = content_.root();
    content_.scan();
    settings_ = ContentLibrary::loadSettings(root_);
}

bool Engine::createWindow() {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSEXW klass{};
    klass.cbSize = sizeof(klass);
    klass.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    klass.lpfnWndProc = &Engine::windowProc;
    klass.hInstance = instance_;
    klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    klass.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    klass.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    klass.lpszClassName = WindowClass;
    RegisterClassExW(&klass);

    RECT desired{0, 0, 1280, 720};
    AdjustWindowRect(&desired, WS_OVERLAPPEDWINDOW, FALSE);
    window_ = CreateWindowExW(0, WindowClass, L"Jave Engine", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                              CW_USEDEFAULT, CW_USEDEFAULT, desired.right - desired.left, desired.bottom - desired.top,
                              nullptr, nullptr, instance_, this);
    if (!window_) return false;
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    if (settings_.fullscreen) toggleFullscreen();
    return true;
}

int Engine::run() {
    if (!createWindow()) throw std::runtime_error("Could not create the Jave Engine window");
    log("Jave Engine 0.1 started");
    lua_.initialize([this](const std::string& line) { log(line); },
                    [this](int r, int g, int b) { accent_ = RGB(r, g, b); },
                    [this](bool flip) { playerFlip_ = flip; });
    std::vector<std::filesystem::path> modRoots;
    for (const auto& mod : content_.mods()) if (mod.enabled) modRoots.push_back(mod.root);
    lua_.loadScripts(root_, modRoots);

    timeBeginPeriod(1);
    constexpr auto frameDuration = std::chrono::duration<double>(1.0 / 60.0);
    auto previous = std::chrono::steady_clock::now();
    auto nextFrame = previous;
    MSG message{};
    while (running_) {
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) running_ = false;
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        const auto now = std::chrono::steady_clock::now();
        if (now < nextFrame) {
            const auto remaining = nextFrame - now;
            if (remaining > std::chrono::milliseconds(2)) Sleep(1);
            else SwitchToThread();
            continue;
        }
        double dt = std::chrono::duration<double>(now - previous).count();
        previous = now;
        nextFrame += std::chrono::duration_cast<std::chrono::steady_clock::duration>(frameDuration);
        if (nextFrame < now) nextFrame = now + std::chrono::duration_cast<std::chrono::steady_clock::duration>(frameDuration);
        dt = std::clamp(dt, 0.0, 0.05);
        update(dt);
        render();
        input_.endFrame();
        mouseLeftPressed_ = false;
        mouseRightPressed_ = false;
        mouseWheelDelta_ = 0;
    }
    timeEndPeriod(1);
    video_.stop();
    audio_.stop();
    return static_cast<int>(message.wParam);
}

LRESULT CALLBACK Engine::windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    Engine* self = reinterpret_cast<Engine*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
        self = static_cast<Engine*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        self->window_ = window;
    }
    return self ? self->handleMessage(window, message, wParam, lParam) : DefWindowProcW(window, message, wParam, lParam);
}

void Engine::updatePointer(HWND window, LPARAM position) {
    RECT client{};
    GetClientRect(window, &client);
    mousePosition_ = RenderViewport::fit(client.right, client.bottom).toCanvas(
        {static_cast<short>(LOWORD(position)), static_cast<short>(HIWORD(position))});
}

LRESULT Engine::handleMessage(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
        input_.onKeyDown(static_cast<unsigned>(wParam));
        return 0;
    case WM_KEYUP: case WM_SYSKEYUP:
        input_.onKeyUp(static_cast<unsigned>(wParam));
        return 0;
    case WM_MOUSEMOVE:
        updatePointer(window, lParam);
        return 0;
    case WM_LBUTTONDOWN:
        SetFocus(window);
        updatePointer(window, lParam);
        mouseLeftPressed_ = true;
        return 0;
    case WM_RBUTTONDOWN:
        SetFocus(window);
        updatePointer(window, lParam);
        mouseRightPressed_ = true;
        return 0;
    case WM_MOUSEWHEEL:
        mouseWheelDelta_ += static_cast<short>(HIWORD(wParam));
        return 0;
    case WM_SIZE:
        renderer_.resize(window, RenderViewport::CanvasWidth, RenderViewport::CanvasHeight);
        return 0;
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: {
        PAINTSTRUCT paint{};
        BeginPaint(window, &paint);
        EndPaint(window, &paint);
        if (screen_ == Screen::Cutscene) video_.repaint();
        return 0;
    }
    case WM_DESTROY:
        video_.stop();
        running_ = false;
        PostQuitMessage(0);
        return 0;
    default: return DefWindowProcW(window, message, wParam, lParam);
    }
}

void Engine::update(double dt) {
    globalTime_ += dt;
    fpsAccumulator_ += dt;
    ++fpsFrames_;
    if (fpsAccumulator_ >= 0.5) {
        fps_ = fpsFrames_ / fpsAccumulator_;
        fpsAccumulator_ = 0.0;
        fpsFrames_ = 0;
    }
    if (screen_ != Screen::Paused && screen_ != Screen::ChartEditor && screen_ != Screen::Cutscene) lua_.update(dt);
    selectionTween_ += (static_cast<double>(selection_) - selectionTween_) * std::min(1.0, dt * 14.0);

    if (screen_ == Screen::Cutscene) {
        video_.update();
        if (video_.started() && !cutsceneStartedLogged_) {
            log("Cutscene playback started: " + cutsceneName_);
            cutsceneStartedLogged_ = true;
        }
        if (input_.wasPressed(VK_ESCAPE)) finishCutscene(true);
        else if (input_.wasPressed(VK_RETURN) || input_.wasPressed(VK_SPACE)) {
            log("Cutscene skipped: " + cutsceneName_);
            finishCutscene();
        } else if (video_.finished()) {
            if (FAILED(video_.error())) log("Cutscene playback error: " + std::to_string(video_.error()));
            else log("Cutscene playback ended: " + cutsceneName_);
            finishCutscene();
        }
        return;
    }

    if (rebinding_) {
        if (input_.wasPressed(VK_ESCAPE)) { rebinding_ = false; return; }
        for (int key = 8; key < 255; ++key) {
            if (input_.wasPressed(key)) {
                settings_.keybinds[static_cast<std::size_t>(rebindLane_)] = key;
                rebinding_ = false;
                ContentLibrary::saveSettings(root_, settings_);
                return;
            }
        }
        return;
    }

    if (screen_ == Screen::Playing) {
        if (input_.wasPressed('7') || input_.wasPressed(VK_NUMPAD7)) {
            openChartEditor();
            return;
        }
        if (input_.wasPressed(VK_RETURN)) {
            pauseSong();
            return;
        }
        if (input_.wasPressed(VK_ESCAPE)) {
            audio_.stop();
            switchScreen(playingStory_ ? Screen::Story : Screen::Freeplay);
            playingStory_ = false;
            storyQueue_.clear();
            return;
        }
        updateGameplay(dt);
        return;
    }

    if (screen_ == Screen::ChartEditor) {
        updateChartEditor();
        return;
    }

    if (screen_ == Screen::Paused) {
        if (input_.wasPressed(VK_ESCAPE)) {
            resumeSong();
            return;
        }
        menuInput(3);
        if (input_.wasPressed(VK_RETURN)) {
            if (selection_ == 0) resumeSong();
            else if (selection_ == 1) restartSong();
            else {
                play_.botplay = !play_.botplay;
                log(std::string("Botplay ") + (play_.botplay ? "enabled" : "disabled"));
            }
        }
        return;
    }

    if (input_.wasPressed(VK_ESCAPE)) {
        if (screen_ == Screen::Main) DestroyWindow(window_);
        else switchScreen(Screen::Main);
        return;
    }

    switch (screen_) {
    case Screen::Main:
        menuInput(6);
        if (input_.wasPressed(VK_RETURN)) {
            const Screen destinations[] = {Screen::Story, Screen::Freeplay, Screen::Mods, Screen::Options, Screen::Credits, Screen::Main};
            if (selection_ == 5) DestroyWindow(window_); else switchScreen(destinations[selection_]);
        }
        break;
    case Screen::Story:
        menuInput(static_cast<int>(content_.weeks().size()));
        if (input_.wasPressed(VK_RETURN) && selection_ < static_cast<int>(content_.weeks().size())) startWeek(content_.weeks()[selection_]);
        break;
    case Screen::Freeplay:
        menuInput(static_cast<int>(content_.songs().size()));
        if (input_.wasPressed(VK_RETURN) && selection_ < static_cast<int>(content_.songs().size())) {
            playingStory_ = false;
            startSong(content_.songs()[selection_]);
        }
        break;
    case Screen::Mods:
        menuInput(static_cast<int>(content_.mods().size()));
        if (input_.wasPressed(VK_RETURN) && selection_ < static_cast<int>(content_.mods().size())) {
            try { content_.toggleMod(static_cast<std::size_t>(selection_)); } catch (const std::exception& e) { log(e.what()); }
        }
        break;
    case Screen::Options: {
        menuInput(9);
        const bool left = input_.wasPressed(VK_LEFT);
        const bool right = input_.wasPressed(VK_RIGHT);
        const int direction = right ? 1 : left ? -1 : 0;
        if (direction != 0) {
            if (selection_ == 0) settings_.masterVolume = std::clamp(settings_.masterVolume + direction * 0.05, 0.0, 1.0);
            else if (selection_ == 1) settings_.noteSpeed = std::clamp(settings_.noteSpeed + direction * 0.1, 0.5, 2.5);
            else if (selection_ == 2) settings_.downscroll = !settings_.downscroll;
            else if (selection_ == 3) { settings_.fullscreen = !settings_.fullscreen; toggleFullscreen(); }
            else if (selection_ == 4) settings_.showFps = !settings_.showFps;
            ContentLibrary::saveSettings(root_, settings_);
        }
        if (input_.wasPressed(VK_RETURN)) {
            if (selection_ == 2) settings_.downscroll = !settings_.downscroll;
            else if (selection_ == 3) { settings_.fullscreen = !settings_.fullscreen; toggleFullscreen(); }
            else if (selection_ == 4) settings_.showFps = !settings_.showFps;
            else if (selection_ >= 5) { rebinding_ = true; rebindLane_ = selection_ - 5; }
            ContentLibrary::saveSettings(root_, settings_);
        }
        break;
    }
    case Screen::Credits: case Screen::Results:
        if (screen_ == Screen::Results && input_.wasPressed(VK_RETURN)) {
            if (playingStory_ && storyPosition_ + 1 < storyQueue_.size()) {
                ++storyPosition_;
                startStorySong(*storyQueue_[storyPosition_]);
            } else {
                const Screen destination = playingStory_ ? Screen::Story : Screen::Freeplay;
                playingStory_ = false;
                storyQueue_.clear();
                switchScreen(destination);
            }
        }
        break;
    case Screen::Playing: case Screen::Paused: case Screen::ChartEditor: case Screen::Cutscene: break;
    }
}

void Engine::menuInput(int itemCount) {
    if (itemCount <= 0) { selection_ = 0; return; }
    const bool up = input_.wasPressed(VK_UP) || input_.wasPressed('W');
    const bool down = input_.wasPressed(VK_DOWN) || input_.wasPressed('S');
    previousSelection_ = selection_;
    if (up) selection_ = (selection_ - 1 + itemCount) % itemCount;
    if (down) selection_ = (selection_ + 1) % itemCount;
}

void Engine::switchScreen(Screen next) {
    screen_ = next;
    selection_ = 0;
    previousSelection_ = 0;
    selectionTween_ = 0;
    rebinding_ = false;
}

void Engine::startSong(const Song& song) {
    try {
        play_ = GameplayState{};
        play_.song = song;
        content_.reloadStage(play_.song);
        play_.chart = content_.loadChart(song);
        play_.active = true;
        play_.health = 0.5;
        play_.songTimeMs = 0;
        play_.cameraZoomBase = play_.song.stageZoom;
        log("Stage layout applied: " + song.stage + " revision=" +
            std::to_string(play_.song.stageLayout["revision"].asInt()) +
            " from " + play_.song.stageConfigPath.string());
        if (!audio_.play(song.audioPath, settings_.masterVolume))
            throw std::runtime_error("Could not play song audio");
        play_.songEndMs = audio_.durationMs() > 0.0 ? audio_.durationMs() : play_.chart.durationMs;
        log("Song timeline: " + song.id + " audioEndMs=" + std::to_string(play_.songEndMs) +
            " chartEndMs=" + std::to_string(play_.chart.durationMs));
        playerFlip_ = false;
        lua_.songStart(song.id);
        switchScreen(Screen::Playing);
    } catch (const std::exception& error) {
        log(std::string("Could not start song: ") + error.what());
        MessageBoxW(window_, widen(error.what()).c_str(), L"Jave Engine - Song error", MB_OK | MB_ICONWARNING);
    }
}

void Engine::startStorySong(const Song& song) {
    if (!startCutscene(song, false)) startSong(song);
}

bool Engine::startCutscene(const Song& song, bool outro) {
    if (!playingStory_ || song.weekId != "weekend1") return false;
    try {
        const auto path = content_.cutscenePath(song, outro);
        if (path.empty()) return false;
        audio_.stop();
        play_.active = false;
        if (!video_.start(window_, path, settings_.masterVolume)) {
            log("Cutscene unavailable: " + path.string() + " HRESULT=" + std::to_string(video_.error()));
            return false;
        }
        cutsceneSong_ = song;
        cutsceneName_ = path.filename().string();
        cutsceneOutro_ = outro;
        cutsceneStartedLogged_ = false;
        switchScreen(Screen::Cutscene);
        log("Cutscene opened: " + cutsceneName_ + (outro ? " after " : " before ") + song.id);
        return true;
    } catch (const std::exception& error) {
        log(std::string("Cutscene manifest error: ") + error.what());
        return false;
    }
}

void Engine::finishCutscene(bool cancelled) {
    video_.stop();
    // Clear held skip keys so Enter cannot immediately pause the new song.
    input_ = InputState{};
    if (cancelled) {
        log("Cutscene cancelled: " + cutsceneName_);
        playingStory_ = false;
        storyQueue_.clear();
        switchScreen(Screen::Story);
    } else if (cutsceneOutro_) switchScreen(Screen::Results);
    else startSong(cutsceneSong_);
}

void Engine::restartSong() {
    const Song song = play_.song;
    const bool botplay = play_.botplay;
    log("Song restarted from pause menu: " + song.id);
    startSong(song);
    play_.botplay = botplay;
}

void Engine::pauseSong() {
    if (audio_.playing() && !audio_.pause()) {
        log("Could not pause song audio");
        return;
    }
    log("Game paused: " + play_.song.id);
    switchScreen(Screen::Paused);
}

void Engine::resumeSong() {
    if (audio_.paused() && !audio_.resume()) {
        log("Could not resume song audio");
        return;
    }
    log("Game resumed: " + play_.song.id);
    switchScreen(Screen::Playing);
}

void Engine::openChartEditor() {
    if (audio_.playing() && !audio_.pause()) {
        log("Could not pause audio for chart editor");
        return;
    }
    editor_ = ChartEditorState{};
    editor_.chart = play_.chart;
    const double snap = chartSnapMs(editor_.chart);
    editor_.cursorTimeMs = std::round(play_.songTimeMs / snap) * snap;
    editor_.status = "Editing a temporary copy - nothing has been saved";
    log("Chart editor opened: " + play_.song.id);
    switchScreen(Screen::ChartEditor);
}

void Engine::closeChartEditor() {
    if (audio_.paused() && !audio_.resume()) {
        editor_.status = "Could not resume song audio";
        log(editor_.status);
        return;
    }
    log(std::string("Chart editor closed ") + (editor_.dirty ? "without saving: " : "after save: ") + play_.song.id);
    switchScreen(Screen::Playing);
}

void Engine::updateChartEditor() {
    if (input_.wasPressed(VK_ESCAPE) || input_.wasPressed('7') || input_.wasPressed(VK_NUMPAD7)) {
        closeChartEditor();
        return;
    }

    const double snap = chartSnapMs(editor_.chart);
    const double maximumTime = std::max(60000.0, editor_.chart.durationMs + 60000.0);
    const ChartEditorLayout layout = chartEditorLayout(renderer_.width(), renderer_.height());
    const bool overGrid = pointInBox(mousePosition_, layout.gridX, layout.gridY, layout.gridWidth, layout.gridHeight);
    if (overGrid && mouseWheelDelta_ != 0) {
        const double wheelSteps = static_cast<double>(mouseWheelDelta_) / WHEEL_DELTA;
        editor_.cursorTimeMs = std::clamp(editor_.cursorTimeMs + wheelSteps * snap * 4.0, 0.0, maximumTime);
        editor_.status = "Scrolled chart - click to add or right-click to delete";
        log("Chart editor scrolled with mouse wheel");
    }

    const auto moveCursorToMouse = [&] {
        const int column = std::clamp(static_cast<int>((mousePosition_.x - layout.gridX) / layout.laneWidth), 0, 7);
        editor_.player = column >= 4;
        editor_.lane = column % 4;
        constexpr double visibleTime = 2500.0;
        const float centerY = layout.gridY + layout.gridHeight * 0.5f;
        const double rawTime = editor_.cursorTimeMs +
            (centerY - static_cast<float>(mousePosition_.y)) / (layout.gridHeight * 0.5f) * visibleTime;
        editor_.cursorTimeMs = std::clamp(std::round(rawTime / snap) * snap, 0.0, maximumTime);
    };

    if (overGrid && mouseLeftPressed_) {
        const double timelinePosition = editor_.cursorTimeMs;
        moveCursorToMouse();
        addEditorNote();
        editor_.cursorTimeMs = timelinePosition;
    } else if (overGrid && mouseRightPressed_) {
        const double timelinePosition = editor_.cursorTimeMs;
        moveCursorToMouse();
        deleteEditorNote();
        editor_.cursorTimeMs = timelinePosition;
    }

    double timeMovement = 0.0;
    if (input_.wasPressed('Q')) timeMovement -= snap;
    if (input_.wasPressed('E')) timeMovement += snap;
    if (input_.wasPressed(VK_PRIOR)) timeMovement -= snap * 16.0;
    if (input_.wasPressed(VK_NEXT)) timeMovement += snap * 16.0;
    editor_.cursorTimeMs = std::clamp(editor_.cursorTimeMs + timeMovement, 0.0, maximumTime);

    if (input_.wasPressed(VK_LEFT)) editor_.lane = (editor_.lane + 3) % 4;
    if (input_.wasPressed(VK_RIGHT)) editor_.lane = (editor_.lane + 1) % 4;
    if (input_.wasPressed(VK_TAB)) editor_.player = !editor_.player;
    if (input_.wasPressed('A')) editor_.sustainMs = std::max(0.0, editor_.sustainMs - snap);
    if (input_.wasPressed('D')) editor_.sustainMs = std::min(16000.0, editor_.sustainMs + snap);

    const auto activateAction = [&](int action) {
        if (action == 0) addEditorNote();
        else if (action == 1) deleteEditorNote();
        else if (action == 2) saveChartEditor();
        else closeChartEditor();
    };

    if (mouseLeftPressed_ && !overGrid) {
        for (int action = 0; action < 4; ++action) {
            const float y = layout.actionsY + action * 54.0f;
            if (pointInBox(mousePosition_, layout.panelX + 20, y, layout.panelWidth - 40, 44)) {
                selection_ = action;
                activateAction(action);
                return;
            }
        }
    }

    menuInput(4);
    if (input_.wasPressed(VK_SPACE)) addEditorNote();
    if (input_.wasPressed(VK_RETURN)) activateAction(selection_);
}

void Engine::addEditorNote() {
    const double snap = chartSnapMs(editor_.chart);
    for (Note& note : editor_.chart.notes) {
        if (note.player == editor_.player && note.lane == editor_.lane &&
            std::abs(note.timeMs - editor_.cursorTimeMs) <= snap * 0.20) {
            note.lengthMs = editor_.sustainMs;
            editor_.dirty = true;
            editor_.status = "Updated note at cursor - choose Save Chart to write it";
            log("Editor note updated with mouse/controls");
            return;
        }
    }
    Note note;
    note.timeMs = editor_.cursorTimeMs;
    note.lane = editor_.lane;
    note.lengthMs = editor_.sustainMs;
    note.player = editor_.player;
    editor_.chart.notes.push_back(note);
    std::stable_sort(editor_.chart.notes.begin(), editor_.chart.notes.end(), [](const Note& a, const Note& b) {
        return a.timeMs < b.timeMs;
    });
    editor_.dirty = true;
    editor_.status = "Added note to temporary chart - choose Save Chart to write it";
    log("Editor note added: " + std::string(editor_.player ? "player" : "opponent") +
        " lane " + std::to_string(editor_.lane + 1));
}

void Engine::deleteEditorNote() {
    const double snap = chartSnapMs(editor_.chart);
    auto best = editor_.chart.notes.end();
    double bestDistance = snap * 0.60;
    for (auto note = editor_.chart.notes.begin(); note != editor_.chart.notes.end(); ++note) {
        if (note->player != editor_.player || note->lane != editor_.lane) continue;
        const double distance = std::abs(note->timeMs - editor_.cursorTimeMs);
        if (distance <= bestDistance) {
            bestDistance = distance;
            best = note;
        }
    }
    if (best == editor_.chart.notes.end()) {
        editor_.status = "No matching note close enough to the cursor";
        return;
    }
    editor_.chart.notes.erase(best);
    editor_.dirty = true;
    editor_.status = "Deleted note from temporary chart - choose Save Chart to write it";
    log("Editor note deleted with right-click/controls");
}

void Engine::saveChartEditor() {
    try {
        std::stable_sort(editor_.chart.notes.begin(), editor_.chart.notes.end(), [](const Note& a, const Note& b) {
            return a.timeMs < b.timeMs;
        });
        Json document(Json::Object{});
        document["format"] = "jave-chart-v1";
        document["song"] = editor_.chart.songId;
        document["difficulty"] = editor_.chart.difficulty;
        document["bpm"] = editor_.chart.bpm;
        document["offsetMs"] = editor_.chart.offsetMs;

        Json notes(Json::Array{});
        double durationMs = 0.0;
        for (const Note& note : editor_.chart.notes) {
            Json item(Json::Object{});
            item["timeMs"] = std::max(0.0, note.timeMs - editor_.chart.offsetMs);
            item["lane"] = note.lane;
            item["owner"] = note.player ? "player" : "opponent";
            if (note.lengthMs > 0.0) item["lengthMs"] = note.lengthMs;
            notes.array().push_back(std::move(item));
            durationMs = std::max(durationMs, note.timeMs + note.lengthMs);
        }
        document["notes"] = std::move(notes);

        Json cameraEvents(Json::Array{});
        for (const CameraEvent& event : editor_.chart.cameraEvents) {
            Json item(Json::Object{});
            item["timeMs"] = std::max(0.0, event.timeMs - editor_.chart.offsetMs);
            item["type"] = event.type;
            if (!event.target.empty()) item["target"] = event.target;
            if (event.type == "position") { item["x"] = event.x; item["y"] = event.y; }
            if (event.type == "zoom" || event.type == "setZoom") item["amount"] = event.amount;
            cameraEvents.array().push_back(std::move(item));
        }
        document["cameraEvents"] = std::move(cameraEvents);
        document.writeFile(play_.song.chartPath);

        editor_.chart.durationMs = durationMs + 2000.0;
        play_.chart = editor_.chart;
        editor_.dirty = false;
        editor_.status = "Chart saved successfully";
        log("Chart saved from editor: " + play_.song.chartPath.string());
    } catch (const std::exception& error) {
        editor_.status = std::string("Save failed: ") + error.what();
        log(editor_.status);
    }
}

void Engine::startWeek(const Week& week) {
    storyQueue_.clear();
    for (const std::string& songId : week.songIds) {
        if (const Song* song = content_.findWeekSong(week, songId)) storyQueue_.push_back(song);
    }
    if (storyQueue_.empty()) return;
    playingStory_ = true;
    storyPosition_ = 0;
    startStorySong(*storyQueue_.front());
}

void Engine::updateGameplay(double dt) {
    if (!play_.active) return;
    play_.songTimeMs = audio_.playing() ? audio_.positionMs() : play_.songTimeMs + dt * 1000.0;
    play_.ratingLife = std::max(0.0, play_.ratingLife - dt);
    play_.playerPoseLife = std::max(0.0, play_.playerPoseLife - dt);
    play_.opponentPoseLife = std::max(0.0, play_.opponentPoseLife - dt);
    if (play_.playerPoseLife <= 0) play_.playerPose = -1;
    if (play_.opponentPoseLife <= 0) play_.opponentPose = -1;
    for (double& flash : play_.playerFlash) flash = std::max(0.0, flash - dt);
    for (double& flash : play_.opponentFlash) flash = std::max(0.0, flash - dt);
    if (play_.botplay) {
        for (Note& note : play_.chart.notes) {
            if (note.player && !note.headHit && !note.judged && play_.songTimeMs >= note.timeMs) judgeLane(note.lane);
        }
    } else {
        for (int lane = 0; lane < 4; ++lane) {
            if (input_.wasPressed(settings_.keybinds[static_cast<std::size_t>(lane)])) judgeLane(lane);
        }
    }

    while (play_.nextCameraEvent < play_.chart.cameraEvents.size() &&
           play_.chart.cameraEvents[play_.nextCameraEvent].timeMs <= play_.songTimeMs) {
        const CameraEvent& event = play_.chart.cameraEvents[play_.nextCameraEvent++];
        if (event.type == "focus") {
            play_.cameraFocus = event.target;
            play_.cameraForced = false;
        } else if (event.type == "position") {
            play_.cameraForced = true;
            play_.cameraManualX = event.x;
            play_.cameraManualY = event.y;
        } else if (event.type == "zoom") {
            play_.cameraZoomPulse = std::clamp(play_.cameraZoomPulse + std::abs(event.amount) * 3.0, 0.0, 0.18);
        } else if (event.type == "setZoom") {
            play_.cameraZoomBase = std::clamp(event.amount, 0.55, 1.5);
        }
    }
    const auto& cameraOffset = play_.cameraFocus == "player" ? play_.song.cameraPlayer : play_.song.cameraOpponent;
    double targetPanX = play_.cameraFocus == "player" ? -renderer_.width() * 0.045 : renderer_.width() * 0.045;
    double targetPanY = 0.0;
    if (play_.cameraForced) {
        const double minimumX = std::min({play_.song.playerPosition[0], play_.song.opponentPosition[0], play_.song.girlfriendPosition[0]});
        const double maximumX = std::max({play_.song.playerPosition[0], play_.song.opponentPosition[0], play_.song.girlfriendPosition[0]});
        const double worldCenter = (minimumX + maximumX) * 0.5;
        targetPanX = -(play_.cameraManualX - worldCenter) / std::max(500.0, maximumX - minimumX) * renderer_.width() * 0.12;
        targetPanY = -play_.cameraManualY / 720.0 * renderer_.height() * 0.08;
    } else {
        targetPanX -= cameraOffset[0] / 1280.0 * renderer_.width() * 0.18;
        targetPanY -= cameraOffset[1] / 720.0 * renderer_.height() * 0.18;
    }
    const double cameraEase = std::min(1.0, dt * std::clamp(play_.song.cameraSpeed, 0.25, 8.0) * 5.0);
    play_.cameraPanX += (targetPanX - play_.cameraPanX) * cameraEase;
    play_.cameraPanY += (targetPanY - play_.cameraPanY) * cameraEase;
    play_.cameraZoomPulse = std::max(0.0, play_.cameraZoomPulse - dt * 0.24);

    for (Note& note : play_.chart.notes) {
        if (!note.player && !note.headHit && play_.songTimeMs >= note.timeMs) {
            note.headHit = true;
            note.hit = true;
            play_.opponentFlash[static_cast<std::size_t>(note.lane)] = 0.14;
            play_.opponentPose = note.lane;
            play_.opponentPoseLife = 0.45;
            play_.opponentAnimationMs = play_.songTimeMs;
            if (note.lengthMs <= 0.0) note.judged = true;
        }
        if (!note.player && note.headHit && !note.judged) {
            if (play_.songTimeMs >= note.timeMs + note.lengthMs) note.judged = true;
            else {
                play_.opponentPose = note.lane;
                play_.opponentPoseLife = 0.10;
            }
        } else if (note.player && note.headHit && !note.judged) {
            const bool held = play_.botplay || input_.down[static_cast<std::size_t>(settings_.keybinds[static_cast<std::size_t>(note.lane)])];
            if (held) {
                note.holding = true;
                note.holdReleaseMs = 0.0;
                play_.health = std::min(1.0, play_.health + dt * 0.008);
                play_.playerFlash[static_cast<std::size_t>(note.lane)] = 0.08;
                play_.playerPose = note.lane;
                play_.playerPoseLife = 0.10;
            } else {
                note.holding = false;
                note.holdReleaseMs += dt * 1000.0;
            }
            if (note.holdReleaseMs > 100.0 && play_.songTimeMs < note.timeMs + note.lengthMs) {
                note.judged = true;
                ++play_.misses;
                ++play_.ratings.miss;
                ++play_.judgedCount;
                play_.combo = 0;
                play_.health = std::max(0.0, play_.health - 0.09);
                play_.lastRating = "HOLD BREAK";
                play_.ratingLife = 0.45;
                lua_.noteHit(note.lane, "miss");
            } else if (play_.songTimeMs >= note.timeMs + note.lengthMs) {
                note.judged = true;
                play_.score += 100;
                play_.health = std::min(1.0, play_.health + 0.015);
            }
        } else if (note.player && !note.headHit && !note.judged && play_.songTimeMs - note.timeMs > 180.0) {
            note.judged = true;
            ++play_.misses;
            ++play_.ratings.miss;
            ++play_.judgedCount;
            play_.combo = 0;
            play_.health = std::max(0.0, play_.health - 0.075);
            play_.lastRating = "MISS";
            play_.ratingLife = 0.45;
            lua_.noteHit(note.lane, "miss");
        }
    }
    if (play_.songTimeMs >= play_.songEndMs) finishSong();
}

void Engine::judgeLane(int lane) {
    Note* best = nullptr;
    double bestDelta = 181.0;
    for (Note& note : play_.chart.notes) {
        if (!note.player || note.headHit || note.judged || note.lane != lane) continue;
        const double delta = std::abs(note.timeMs - play_.songTimeMs);
        if (delta < bestDelta) { bestDelta = delta; best = &note; }
        if (note.timeMs - play_.songTimeMs > 180.0) break;
    }
    if (!best) return;
    best->headHit = true;
    best->judged = best->lengthMs <= 0.0;
    best->holding = best->lengthMs > 0.0;
    best->hit = true;
    ++play_.judgedCount;
    ++play_.combo;
    play_.maxCombo = std::max(play_.maxCombo, play_.combo);
    std::string rating;
    if (bestDelta <= 45.0) { rating = "sick"; ++play_.ratings.sick; play_.score += 350; play_.accuracyPoints += 1.0; play_.health += 0.025; }
    else if (bestDelta <= 90.0) { rating = "good"; ++play_.ratings.good; play_.score += 200; play_.accuracyPoints += 0.75; play_.health += 0.015; }
    else { rating = "bad"; ++play_.ratings.bad; play_.score += 100; play_.accuracyPoints += 0.4; play_.health += 0.005; }
    play_.health = std::clamp(play_.health, 0.0, 1.0);
    play_.lastRating = rating;
    std::transform(play_.lastRating.begin(), play_.lastRating.end(), play_.lastRating.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    play_.ratingLife = 0.45;
    play_.playerFlash[static_cast<std::size_t>(lane)] = 0.14;
    play_.playerPose = lane;
    play_.playerPoseLife = 0.45;
    play_.playerAnimationMs = play_.songTimeMs;
    lua_.noteHit(lane, rating);
}

void Engine::finishSong() {
    audio_.stop();
    play_.active = false;
    if (startCutscene(play_.song, true)) return;
    switchScreen(Screen::Results);
}

void Engine::toggleFullscreen() {
    const bool makeFullscreen = settings_.fullscreen;
    if (makeFullscreen) {
        windowedStyle_ = static_cast<DWORD>(GetWindowLongPtrW(window_, GWL_STYLE));
        GetWindowRect(window_, &windowedRect_);
        MONITORINFO info{};
        info.cbSize = sizeof(info);
        GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &info);
        SetWindowLongPtrW(window_, GWL_STYLE, windowedStyle_ & ~WS_OVERLAPPEDWINDOW);
        SetWindowPos(window_, HWND_TOP, info.rcMonitor.left, info.rcMonitor.top,
                     info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top,
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    } else if (windowedStyle_ != 0) {
        SetWindowLongPtrW(window_, GWL_STYLE, windowedStyle_);
        SetWindowPos(window_, nullptr, windowedRect_.left, windowedRect_.top,
                     windowedRect_.right - windowedRect_.left, windowedRect_.bottom - windowedRect_.top,
                     SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    }
}

void Engine::log(const std::string& message) {
    try {
        std::filesystem::create_directories(root_ / "saves");
        std::ofstream file(root_ / "saves" / "jave.log", std::ios::app);
        file << message << '\n';
    } catch (...) {}
}

void Engine::render() {
    if (!window_ || !IsWindowVisible(window_)) return;
    RECT client{};
    GetClientRect(window_, &client);
    const int outputWidth = std::max(1L, client.right);
    const int outputHeight = std::max(1L, client.bottom);
    constexpr int width = RenderViewport::CanvasWidth;
    constexpr int height = RenderViewport::CanvasHeight;
    renderer_.resize(window_, width, height);
    if (screen_ == Screen::Cutscene) {
        const auto viewport = RenderViewport::fit(outputWidth, outputHeight);
        video_.resize(viewport.width, std::max(1, viewport.height - static_cast<int>(std::round(34.0 * viewport.height / height))),
                      viewport.x, viewport.y);
        HDC target = GetDC(window_);
        renderer_.begin(target, width, height);
        renderer_.rect(0, 0, static_cast<float>(width), static_cast<float>(height), RGB(0, 0, 0));
        renderer_.text(L"ENTER / SPACE: Skip cutscene     ESC: Back to Story Mode", 12, height - 34.0f,
                       width - 24.0f, 34, 14, RGB(220, 220, 220), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        renderer_.end(target, outputWidth, outputHeight);
        ReleaseDC(window_, target);
        video_.repaint();
        return;
    }
    HDC target = GetDC(window_);
    renderer_.begin(target, width, height);
    if (screen_ == Screen::Playing || screen_ == Screen::Paused) renderer_.clearGradient(RGB(5, 6, 12), RGB(10, 10, 20));
    else drawBackdrop();
    switch (screen_) {
    case Screen::Main: drawMain(); break;
    case Screen::Story: drawStory(); break;
    case Screen::Freeplay: drawFreeplay(); break;
    case Screen::Mods: drawMods(); break;
    case Screen::Options: drawOptions(); break;
    case Screen::Credits: drawCredits(); break;
    case Screen::Playing: drawGameplay(); break;
    case Screen::Paused: drawGameplay(); drawPause(); break;
    case Screen::ChartEditor: drawChartEditor(); break;
    case Screen::Results: drawResults(); break;
    case Screen::Cutscene: break;
    }
    if (settings_.showFps) renderer_.text(std::to_wstring(static_cast<int>(fps_)) + L" FPS", width - 100.0f, 12, 80, 25, 14, RGB(145, 158, 190), DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    renderer_.end(target, outputWidth, outputHeight);
    ReleaseDC(window_, target);
}

float Engine::drawFunkinLabel(const std::wstring& value, float x, float y, float width, float height) {
    const float startX = x;
    static std::map<std::wstring, Json> fonts;
    const auto glyphManifest = content_.assetPath("assets/imported/menus/alphabet/glyphs.json");
    const auto folder = glyphManifest.parent_path();
    const auto key = folder.wstring();
    if (!fonts.contains(key)) {
        try { fonts.emplace(key, Json::fromFile(glyphManifest)); }
        catch (...) { fonts.emplace(key, Json::Object{}); }
    }
    const Json& font = fonts.at(key);
    double naturalWidth = 0;
    for (wchar_t letter : value) {
        const char ch = letter < 128 ? static_cast<char>(std::toupper(static_cast<unsigned char>(letter))) : '?';
        naturalWidth += ch == ' ' ? 36 : font[std::string(1, ch)]["width"].asNumber(40) + 7;
    }
    const double scale = std::min(height / 80.0, width / std::max(1.0, naturalWidth));
    for (wchar_t letter : value) {
        const char ch = letter < 128 ? static_cast<char>(std::toupper(static_cast<unsigned char>(letter))) : '?';
        if (ch == ' ') { x += static_cast<float>(36 * scale); continue; }
        const Json& glyph = font[std::string(1, ch)];
        const float w = static_cast<float>(glyph["width"].asNumber(40) * scale);
        const float h = static_cast<float>(glyph["height"].asNumber(65) * scale);
        if (!glyph["file"].asString().empty())
            renderer_.image(folder / glyph["file"].asString(), x, y + height - h, w, h);
        else renderer_.text(std::wstring(1, letter), x, y, w, height, static_cast<int>(height * 0.7f), RGB(255,255,255), DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
        x += w + static_cast<float>(7 * scale);
    }
    return x - startX;
}

void Engine::drawBackdrop() {
    const int width = renderer_.width();
    const int height = renderer_.height();
    if (screen_ >= Screen::Main && screen_ <= Screen::Credits) {
        const wchar_t* background = screen_ == Screen::Main || screen_ == Screen::Story ? L"menuBG.png" :
            screen_ == Screen::Freeplay ? L"menuPurple.png" : L"menuCool.png";
        renderer_.clearGradient(RGB(252,219,92), RGB(219,141,180));
        const float zoom = 1.025f + static_cast<float>(std::sin(globalTime_ * 1.7) * .004);
        renderer_.image(content_.assetPath(std::filesystem::path("assets/imported/menus") / background),
                        width * (1 - zoom) * .5f, height * (1 - zoom) * .5f, width * zoom, height * zoom, false, true);
        return;
    }
    renderer_.clearGradient(RGB(10, 13, 34), RGB(25, 12, 43));
    for (int i = 0; i < 11; ++i) {
        const double phase = globalTime_ * (0.14 + i * 0.008) + i * 1.7;
        const float size = static_cast<float>(110 + (i % 4) * 38);
        const float x = static_cast<float>((std::sin(phase) * 0.45 + 0.5) * (width + size) - size);
        const float y = static_cast<float>((std::cos(phase * 0.73 + i) * 0.45 + 0.5) * (height + size) - size);
        renderer_.ellipse(x, y, size, size, mixColor(RGB(17, 20, 48), i % 2 ? accent_ : accent2_, 0.10));
    }
    const float lineY = static_cast<float>(height * 0.82 + std::sin(globalTime_ * 0.8) * 8.0);
    renderer_.rect(0, lineY, static_cast<float>(width), 2, mixColor(RGB(20, 24, 50), accent_, 0.35));
}

void Engine::drawHeader(const std::wstring& eyebrow, const std::wstring& title, const std::wstring& subtitle) {
    if (screen_ >= Screen::Main && screen_ <= Screen::Credits) {
        renderer_.rect(0, 0, static_cast<float>(renderer_.width()), 115, RGB(22,18,31));
        drawFunkinLabel(title, 35, 18, static_cast<float>(renderer_.width()-70), 59);
        renderer_.text(subtitle, 40, 82, static_cast<float>(renderer_.width()-80), 25, 15, RGB(245,235,255));
        return;
    }
    renderer_.text(eyebrow, 64, 42, 700, 30, 15, accent_, DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(title, 60, 70, 1000, 68, 46, RGB(245, 247, 255), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    if (!subtitle.empty()) renderer_.text(subtitle, 64, 132, 950, 36, 18, RGB(152, 162, 195));
}

void Engine::drawMenu(const std::vector<std::wstring>& items, float startY, float width) {
    const float x = 60.0f;
    const float row = screen_ == Screen::Story ? 78.0f : 70.0f;
    const int count = static_cast<int>(items.size());
    const float focus = std::max(startY + 55, renderer_.height() * .48f);
    const int first = std::max(0, selection_ - 4);
    const int last = std::min(count, selection_ + 5);
    for (int i = first; i < last; ++i) {
        const bool selected = static_cast<int>(i) == selection_;
        const float distance = static_cast<float>(i - selectionTween_);
        const float offset = selected ? 34.0f : 10.0f + std::abs(distance) * 12.0f;
        const float y = focus + distance * row;
        if (y < startY - 10 || y > renderer_.height() - 88) continue;
        if (selected) renderer_.text(L">", x - 28, y, 40, 55, 32, RGB(255,255,255), DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
        float labelWidth = 0;
        bool usedWeekArt = false;
        if (screen_ == Screen::Story && static_cast<std::size_t>(i) < content_.weeks().size()) {
            const auto& week = content_.weeks()[static_cast<std::size_t>(i)];
            auto path = week.packageRoot / "assets/imported/menus/weeks" / (week.id + ".png");
            if (!std::filesystem::is_regular_file(path))
                path = content_.assetPath(std::filesystem::path("assets/imported/menus/weeks") / (week.id + ".png"));
            static std::map<std::wstring, bool> available;
            const auto key = path.wstring();
            if (!available.contains(key)) available.emplace(key, std::filesystem::is_regular_file(path));
            if (available.at(key)) {
                renderer_.image(path, x + offset, y, width - 85, selected ? 62 : 48);
                usedWeekArt = true;
            }
        }
        if (!usedWeekArt) labelWidth = drawFunkinLabel(items[i], x + offset, y, width - 70, selected ? 56 : 43);
        if (screen_ == Screen::Freeplay && static_cast<std::size_t>(i) < content_.songs().size())
            renderer_.image(content_.songs()[static_cast<std::size_t>(i)].opponentIcon,
                            std::min(x + width - 45, x + offset + labelWidth + 15), y + 7, 50, 50);
    }
    renderer_.rect(0, static_cast<float>(renderer_.height()-42), static_cast<float>(renderer_.width()), 42, RGB(22,18,31));
    renderer_.text(L"UP / DOWN: SELECT     ENTER: CONFIRM     ESC: BACK", 30, static_cast<float>(renderer_.height()-38), 800, 30, 16, RGB(245,235,255));
}

void Engine::drawMain() {
    const float width = static_cast<float>(renderer_.width());
    const float height = static_cast<float>(renderer_.height());
    drawFunkinLabel(L"JAVE ENGINE", width * .61f, height * .065f, width * .36f, height * .075f);
    const wchar_t* ids[] = {L"story_mode",L"freeplay",L"mods",L"options",L"credits"};
    for (int i = 0; i < 6; ++i) {
        const bool selected = i == selection_;
        const float y = height * (.075f + i * .138f);
        const float x = width * (selected ? .105f : .075f);
        const float h = height * (selected ? .113f : .094f);
        if (i == 5) { drawFunkinLabel(L"EXIT", x + 30, y, width * .35f, h * .8f); continue; }
        const auto base = content_.assetPath(std::filesystem::path("assets/imported/menus/buttons") / ids[i]);
        const Json& metadata = characterMetadata(base)[selected ? "left" : "idle"];
        if (metadata.isNull()) {
            const wchar_t* labels[] = {L"STORY MODE", L"FREEPLAY", L"MODS", L"OPTIONS", L"CREDITS"};
            drawFunkinLabel(labels[i], x, y, width * .50f, h * .82f);
            continue;
        }
        const float nativeW = static_cast<float>(metadata["width"].asNumber(600));
        const float nativeH = static_cast<float>(metadata["height"].asNumber(120));
        const float w = std::min(width * .54f, h * nativeW / std::max(1.0f,nativeH));
        renderer_.image(animatedPosePath(base, selected ? 0 : -1, globalTime_), x, y, w, h);
        if (i == 3) drawFunkinLabel(L"OPTIONS", x + h * 1.18f, y + 6, width * .36f, h * .82f);
    }
    renderer_.rect(0, height - 38, width, 38, RGB(22,18,31));
    renderer_.text(L"Jave Engine 0.1     UP / DOWN: SELECT     ENTER: CONFIRM", 25, height - 34, width - 50, 28, 15, RGB(250,245,255));
}

void Engine::drawStory() {
    drawHeader(L"CAMPAIGN", L"STORY MODE", L"Choose a week - NORMAL difficulty");
    if (content_.weeks().empty()) {
        renderer_.text(L"No weeks found. Enable a mod containing data/weeks.json", 64, 250, 900, 50, 24, RGB(255, 150, 170));
        return;
    }
    std::vector<std::wstring> labels;
    for (const Week& week : content_.weeks()) labels.push_back(widen(week.name));
    const Week& week = content_.weeks()[static_cast<std::size_t>(selection_)];
    const float width = static_cast<float>(renderer_.width());
    const float height = static_cast<float>(renderer_.height());
    renderer_.rect(0, 120, width, height * .37f, RGB(249,202,89));
    const Song* preview = week.songIds.empty() ? nullptr : content_.findWeekSong(week, week.songIds.front());
    if (preview) {
        const double idleTime = std::fmod(globalTime_,1.0);
        const auto character = [&](const std::filesystem::path& base, float center, float h, bool player) {
            renderer_.image(animatedPosePath(base,-1,idleTime), center - width*.12f,
                            130 + height*.34f-h, width*.24f,h,
                            characterMetadata(base)["flipX"].asBool(false) != player);
        };
        if (preview->opponentCharacter != preview->girlfriendCharacter)
            character(preview->opponentVisual,width*.22f,height*.30f,false);
        if (!preview->hideGirlfriend) character(preview->girlfriendVisual,width*.49f,height*.29f,false);
        character(preview->playerVisual,width*.75f,height*.24f,true);
    }
    drawMenu(labels, height*.57f, width*.46f);
    const float panelX = width * .58f;
    drawFunkinLabel(L"TRACKS", panelX, height*.57f, width*.36f, 42);
    float y = height*.64f;
    for (std::size_t index = 0; index < week.songIds.size(); ++index) {
        const Song* song = content_.findWeekSong(week, week.songIds[index]);
        drawFunkinLabel(widen(song ? song->title : week.songIds[index]), panelX, y, width*.38f, 29);
        y += 35;
    }
}

void Engine::drawFreeplay() {
    drawHeader(L"SONG LIBRARY", L"FREEPLAY", L"Pick any installed chart.");
    if (content_.songs().empty()) {
        renderer_.text(L"No valid songs found", 64, 240, 700, 50, 26, RGB(255, 150, 170), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
        return;
    }
    std::vector<std::wstring> items;
    for (const auto& song : content_.songs()) items.push_back(widen(song.title));
    drawMenu(items, 145, static_cast<float>(renderer_.width())*.64f);
    const Song& song = content_.songs()[static_cast<std::size_t>(selection_)];
    const float x = static_cast<float>(renderer_.width())*.70f;
    const float w = static_cast<float>(renderer_.width())*.27f;
    renderer_.rect(x,145,w,135,RGB(22,18,31));
    drawFunkinLabel(L"NORMAL",x+20,160,w-40,39);
    renderer_.text(std::to_wstring(static_cast<int>(song.bpm))+L" BPM",x+20,212,w-40,30,22,RGB(255,255,255),DT_CENTER|DT_VCENTER|DT_SINGLELINE,true);
    renderer_.text(widen(song.artist),x+10,248,w-20,25,13,RGB(225,220,240),DT_CENTER|DT_VCENTER|DT_SINGLELINE);
    renderer_.image(song.playerIcon,x+w*.25f,340,w*.50f,150);
}

void Engine::drawMods() {
    drawHeader(L"CONTENT PACKAGES", L"MODS", L"Enter toggles a package. Restart to reload its scripts.");
    if (content_.mods().empty()) {
        renderer_.text(L"Drop packages into mods/<mod-id>/", 64, 240, 800, 50, 24, RGB(190,198,225));
        return;
    }
    std::vector<std::wstring> items;
    for (const auto& mod : content_.mods()) items.push_back((mod.enabled ? L"●  " : L"○  ") + widen(mod.name));
    drawMenu(items, 205, static_cast<float>(renderer_.width())*.42f);
    const auto& mod = content_.mods()[static_cast<std::size_t>(selection_)];
    const float x = static_cast<float>(renderer_.width() - 515);
    renderer_.rect(x, 205, 450, 260, RGB(22,18,31), 0);
    renderer_.text(widen(mod.name), x + 30, 230, 390, 48, 29, RGB(250,250,255), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(L"v" + widen(mod.version) + L"  •  " + widen(mod.author), x + 30, 280, 390, 30, 16, accent_);
    renderer_.text(widen(mod.description), x + 30, 325, 390, 75, 17, RGB(160,170,201), DT_LEFT | DT_WORDBREAK);
    renderer_.text(mod.enabled ? L"ENABLED" : L"DISABLED", x + 30, 410, 180, 30, 16, mod.enabled ? RGB(105,235,176) : RGB(255,135,160), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
}

void Engine::drawOptions() {
    drawHeader(L"PERSONALIZE", L"OPTIONS", rebinding_ ? L"Press a key, or Escape to cancel." : L"Use Left/Right to adjust. Enter rebinding items.");
    const wchar_t* lanes[] = {L"Left Key", L"Down Key", L"Up Key", L"Right Key"};
    std::vector<std::wstring> items = {
        L"Master Volume     " + percent(settings_.masterVolume),
        L"Note Speed        " + std::to_wstring(settings_.noteSpeed).substr(0, 3) + L"x",
        L"Scroll Direction  " + std::wstring(settings_.downscroll ? L"Down" : L"Up"),
        L"Fullscreen        " + std::wstring(settings_.fullscreen ? L"On" : L"Off"),
        L"Show FPS          " + std::wstring(settings_.showFps ? L"On" : L"Off")
    };
    for (int i = 0; i < 4; ++i) items.push_back(std::wstring(lanes[i]) + L"          " + keyName(settings_.keybinds[static_cast<std::size_t>(i)]));
    drawMenu(items, 175, 670);
    if (rebinding_) {
        renderer_.rect(static_cast<float>(renderer_.width() / 2 - 260), static_cast<float>(renderer_.height() / 2 - 85), 520, 170, RGB(28, 31, 66), 26);
        renderer_.outline(static_cast<float>(renderer_.width() / 2 - 260), static_cast<float>(renderer_.height() / 2 - 85), 520, 170, accent_, 3, 26);
        renderer_.text(L"PRESS A NEW KEY", static_cast<float>(renderer_.width() / 2 - 220), static_cast<float>(renderer_.height() / 2 - 50), 440, 60, 30, RGB(255,255,255), DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
        renderer_.text(L"Escape cancels", static_cast<float>(renderer_.width() / 2 - 220), static_cast<float>(renderer_.height() / 2 + 15), 440, 30, 16, RGB(160,170,200), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }
}

void Engine::drawCredits() {
    drawHeader(L"PEOPLE & LICENSES", L"CREDITS", L"Built cleanly, from the first beat.");
    renderer_.rect(64, 205, static_cast<float>(renderer_.width() - 128), 360, RGB(22,18,31), 0);
    renderer_.text(L"JAVE ENGINE", 105, 235, 450, 48, 29, accent_, DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(L"Original C++ engine; imported media retains its authors' rights", 105, 285, 850, 38, 18, RGB(220,224,240));
    renderer_.text(L"Lua 5.4.8", 105, 355, 330, 40, 24, RGB(250,250,255), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(L"Lua.org, PUC-Rio  •  MIT License", 105, 394, 650, 30, 17, RGB(156,166,198));
    renderer_.text(L"Independent project — not affiliated with The Funkin' Crew, Psych Engine, or V-Slice.", 105, 465, 950, 35, 17, RGB(184,192,216));
    renderer_.text(L"Source license: MIT  •  Demo song/chart: CC0", 105, 510, 750, 30, 16, accent2_);
}

void Engine::drawGameplay() {
    const int width = renderer_.width();
    const int height = renderer_.height();
    const float cameraScale = static_cast<float>(std::clamp(1.0 + (play_.cameraZoomBase - 0.9) * 0.22 + play_.cameraZoomPulse, 0.88, 1.22));
    const float stageWidth = width * cameraScale;
    const float stageHeight = height * cameraScale;
    renderer_.image(play_.song.stageImage, (width - stageWidth) * 0.5f + static_cast<float>(play_.cameraPanX),
                    (height - stageHeight) * 0.5f + static_cast<float>(play_.cameraPanY), stageWidth, stageHeight);

    const Json& layout = play_.song.stageLayout;
    const auto stageBox = [&](const std::array<double, 2>& position, const char* role, float widthRatio, float heightRatio) {
        const float boxWidth = width * widthRatio;
        const float boxHeight = height * heightRatio;
        const Json& placement = layout["placements"][role];
        const auto& anchor = placement["anchor"].asArray();
        double centerX = 170.0 + position[0] * 0.9;
        double floorY = 535.0 + position[1] * 0.25;
        if (anchor.size() == 2) {
            centerX = anchor[0].asNumber();
            floorY = anchor[1].asNumber();
            // Retain source-coordinate editing after mapping into the baked
            // stage image. Moving one character never repositions another.
            const auto& source = placement["sourceAnchor"].asArray();
            if (source.size() == 2) {
                const double units = layout["positionScale"].asNumber(0.5);
                centerX += (position[0] - source[0].asNumber()) * units;
                floorY += (position[1] - source[1].asNumber()) * units;
            }
        }
        const double referenceW = std::max(1.0, layout["width"].asNumber(1280));
        const double referenceH = std::max(1.0, layout["height"].asNumber(720));
        float x = static_cast<float>(centerX / referenceW * width) - boxWidth * 0.5f;
        float y = static_cast<float>(floorY / referenceH * height) - boxHeight;
        x = (x - width * 0.5f) * cameraScale + width * 0.5f + static_cast<float>(play_.cameraPanX);
        y = (y - height * 0.5f) * cameraScale + height * 0.5f + static_cast<float>(play_.cameraPanY);
        return std::array<float, 4>{x, y, boxWidth * cameraScale, boxHeight * cameraScale};
    };
    const double beatMs = 60000.0 / std::max(1.0, play_.chart.bpm);
    const double idleTime = std::fmod(play_.songTimeMs, beatMs * 2.0) / 1000.0;
    const auto drawCharacter = [&](const std::filesystem::path& base,
                                   const std::array<double, 2>& position, int pose,
                                   double animationTime, bool player, const char* role) {
        const Json& meta = characterMetadata(base);
        const double idleW = std::max(1.0, meta["idle"]["width"].asNumber(420.0));
        const double idleH = std::max(1.0, meta["idle"]["height"].asNumber(500.0));
        if (pose < 0 && meta["danceRight"]["frames"].asNumber() > 0) {
            pose = static_cast<int>(play_.songTimeMs / beatMs) % 2 ? 4 : -1;
            animationTime = std::fmod(play_.songTimeMs, beatMs) / 1000.0;
        }
        const auto speakerPath = meta["speaker"]["assetPath"].asString();
        const bool hasSpeaker = !speakerPath.empty();
        const auto speakerBase = base / std::filesystem::path(speakerPath);
        const Json& speaker = hasSpeaker ? characterMetadata(speakerBase) : meta;
        const double speakerW = hasSpeaker ? speaker["idle"]["width"].asNumber() : 0;
        const double speakerH = hasSpeaker ? speaker["idle"]["height"].asNumber() : 0;
        const double overlap = hasSpeaker ? std::clamp(meta["speaker"]["overlap"].asNumber(), 0.0, speakerH) : 0;
        const double combinedW = std::max(idleW, speakerW);
        const double combinedH = idleH + speakerH - overlap;
        const double sourceScale = std::clamp(meta["scale"].asNumber(1.0) *
            layout["placements"][role]["scale"].asNumber(1.0), 0.05, 10.0);
        const double scale = std::min({height / 720.0 * 0.72 * sourceScale,
                                      width * (hasSpeaker ? 0.42 : 0.36) / combinedW, height * 0.62 / combinedH});
        const auto box = stageBox(position, role, static_cast<float>(combinedW * scale / width),
                                  static_cast<float>(combinedH * scale / height));
        if (hasSpeaker) {
            const float propW = static_cast<float>(speakerW * scale * cameraScale);
            const float propH = static_cast<float>(speakerH * scale * cameraScale);
            renderer_.image(animatedPosePath(speakerBase, -1, std::fmod(play_.songTimeMs, beatMs) / 1000.0),
                            box[0] + (box[2] - propW) * 0.5f, box[1] + box[3] - propH, propW, propH);
        }
        const char* key = pose < 0 ? "idle" : pose == 0 ? "left" : pose == 1 ? "down" : pose == 2 ? "up" : pose == 4 ? "danceRight" : "right";
        const Json& anim = meta[key];
        const float drawW = static_cast<float>(anim["width"].asNumber(idleW) * scale * cameraScale);
        const float drawH = static_cast<float>(anim["height"].asNumber(idleH) * scale * cameraScale);
        const bool flip = meta["flipX"].asBool(false) != player;
        renderer_.image(animatedPosePath(base, pose, animationTime),
                        box[0] + (box[2] - drawW) * 0.5f,
                        box[1] + box[3] - drawH - static_cast<float>((speakerH - overlap) * scale * cameraScale),
                        drawW, drawH, flip != (player && playerFlip_));
    };
    if (!play_.song.hideGirlfriend)
        drawCharacter(play_.song.girlfriendVisual, play_.song.girlfriendPosition, -1, idleTime, false, "girlfriend");
    drawCharacter(play_.song.opponentVisual, play_.song.opponentPosition, play_.opponentPose,
                  play_.opponentPose < 0 ? idleTime : (play_.songTimeMs - play_.opponentAnimationMs) / 1000.0, false, "opponent");
    drawCharacter(play_.song.playerVisual, play_.song.playerPosition, play_.playerPose,
                  play_.playerPose < 0 ? idleTime : (play_.songTimeMs - play_.playerAnimationMs) / 1000.0, true, "player");

    const float laneWidth = std::clamp(width * 0.0875f, 78.0f, 112.0f);
    const float groupWidth = laneWidth * 4.0f;
    const float opponentX = width * 0.025f;
    const float playerX = width - opponentX - groupWidth;
    const float receptorY = settings_.downscroll ? height - 135.0f : 90.0f;
    for (int lane = 0; lane < 4; ++lane) {
        const bool held = input_.down[static_cast<std::size_t>(settings_.keybinds[static_cast<std::size_t>(lane)])];
        const bool opponentConfirmed = play_.opponentFlash[static_cast<std::size_t>(lane)] > 0;
        const bool playerConfirmed = play_.playerFlash[static_cast<std::size_t>(lane)] > 0;
        const wchar_t* opponentKind = opponentConfirmed ? L"confirm" : L"receptor";
        const wchar_t* playerKind = playerConfirmed ? L"confirm" : held ? L"press" : L"receptor";
        const float opponentSize = laneWidth * (opponentConfirmed ? 1.34f : 0.98f);
        const float playerSize = laneWidth * (playerConfirmed ? 1.34f : 0.98f);
        const float opponentCenter = opponentX + (lane + 0.5f) * laneWidth;
        const float playerCenter = playerX + (lane + 0.5f) * laneWidth;
        renderer_.image(noteImagePath(root_, opponentKind, lane), opponentCenter - opponentSize * 0.5f,
                        receptorY - opponentSize * 0.5f, opponentSize, opponentSize);
        renderer_.image(noteImagePath(root_, playerKind, lane), playerCenter - playerSize * 0.5f,
                        receptorY - playerSize * 0.5f, playerSize, playerSize);
    }

    const double pixelsPerMs = 0.36 * settings_.noteSpeed;
    for (const Note& note : play_.chart.notes) {
        if (note.judged) continue;
        const double visibleStartMs = note.headHit ? play_.songTimeMs : note.timeMs;
        const double distance = (visibleStartMs - play_.songTimeMs) * pixelsPerMs;
        float y = settings_.downscroll ? static_cast<float>(receptorY - distance) : static_cast<float>(receptorY + distance);
        if (y < -100 || y > height + 100) continue;
        const float groupX = note.player ? playerX : opponentX;
        const float centerX = groupX + (note.lane + 0.5f) * laneWidth;
        if (note.lengthMs > 0) {
            const double remainingMs = std::max(0.0, note.timeMs + note.lengthMs - visibleStartMs);
            const float sustain = static_cast<float>(remainingMs * pixelsPerMs);
            const float tailY = settings_.downscroll ? y - sustain : y;
            if (sustain > 0.0f) {
                renderer_.image(noteImagePath(root_, L"hold", note.lane), centerX - laneWidth * 0.12f, tailY,
                                laneWidth * 0.24f, sustain, false, true);
                const float endSize = laneWidth * 0.34f;
                const float endY = settings_.downscroll ? tailY - endSize * 0.5f : tailY + sustain - endSize * 0.5f;
                renderer_.image(noteImagePath(root_, L"hold_end", note.lane), centerX - endSize * 0.5f, endY, endSize, endSize);
            }
        }
        if (!note.headHit) {
            const float noteSize = laneWidth * 0.98f;
            renderer_.image(noteImagePath(root_, L"note", note.lane), centerX - noteSize * 0.5f,
                            y - noteSize * 0.5f, noteSize, noteSize);
        }
    }

    const float healthX = 115.0f;
    const float healthW = static_cast<float>(width - 230);
    const float healthY = static_cast<float>(height - 50);
    renderer_.rect(healthX, healthY, healthW, 22, RGB(245,245,250), 10);
    renderer_.rect(healthX + 3, healthY + 3, healthW - 6, 16, RGB(220,50,70), 8);
    renderer_.rect(healthX + 3 + (healthW - 6) * static_cast<float>(1.0 - play_.health), healthY + 3,
                   (healthW - 6) * static_cast<float>(play_.health), 16, RGB(45,205,95), 8);
    renderer_.image(play_.song.opponentIcon, 34, healthY - 48, 86, 78);
    renderer_.image(play_.song.playerIcon, static_cast<float>(width - 120), healthY - 48, 86, 78, true);
    const double accuracy = play_.judgedCount > 0 ? play_.accuracyPoints / play_.judgedCount : 1.0;
    renderer_.text(L"ACCURACY  " + percent(accuracy) + L"    MISSES  " + std::to_wstring(play_.misses), healthX, healthY - 32, 500, 28, 15, RGB(255,255,255), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    if (play_.botplay) {
        renderer_.rect(static_cast<float>(width / 2 - 72), 24, 144, 34, RGB(20, 23, 52), 12);
        renderer_.outline(static_cast<float>(width / 2 - 72), 24, 144, 34, accent_, 2, 12);
        renderer_.text(L"BOTPLAY", static_cast<float>(width / 2 - 66), 24, 132, 34, 16, accent_, DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
    }
    if (play_.ratingLife > 0) renderer_.text(widen(play_.lastRating), static_cast<float>(width / 2 - 180), static_cast<float>(height / 2 - 55), 360, 110, 54, RGB(255,255,255), DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
}

void Engine::drawPause() {
    const float panelWidth = 520.0f;
    const float panelHeight = 440.0f;
    const float panelX = (renderer_.width() - panelWidth) * 0.5f;
    const float panelY = (renderer_.height() - panelHeight) * 0.5f;
    renderer_.rect(panelX - 8, panelY + 10, panelWidth + 16, panelHeight + 8, RGB(4, 5, 13), 34);
    renderer_.rect(panelX, panelY, panelWidth, panelHeight, RGB(18, 21, 48), 30);
    renderer_.outline(panelX, panelY, panelWidth, panelHeight, mixColor(RGB(40, 45, 80), accent_, 0.62), 3, 30);
    renderer_.text(L"PAUSED", panelX + 40, panelY + 30, panelWidth - 80, 62, 42, RGB(250, 251, 255), DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(widen(play_.song.title), panelX + 40, panelY + 88, panelWidth - 80, 32, 17, accent_, DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);

    const std::vector<std::wstring> items{
        L"Resume",
        L"Restart Song",
        std::wstring(L"Botplay    ") + (play_.botplay ? L"ON" : L"OFF")
    };
    const float rowX = panelX + 58.0f;
    const float rowWidth = panelWidth - 116.0f;
    const float startY = panelY + 145.0f;
    for (std::size_t index = 0; index < items.size(); ++index) {
        const bool selected = static_cast<int>(index) == selection_;
        const float y = startY + static_cast<float>(index) * 64.0f;
        const float offset = selected ? 8.0f + static_cast<float>(std::sin(globalTime_ * 6.0) * 2.0) : 0.0f;
        if (selected) {
            renderer_.rect(rowX + offset, y, rowWidth, 52, mixColor(RGB(30, 34, 68), accent_, 0.24), 16);
            renderer_.rect(rowX + offset, y + 10, 5, 32, accent_, 3);
        }
        const COLORREF labelColor = selected ? RGB(255, 255, 255) : RGB(160, 170, 204);
        renderer_.text(items[index], rowX + 24 + offset, y, rowWidth - 40, 52, selected ? 24 : 21,
                       labelColor, DT_LEFT | DT_VCENTER | DT_SINGLELINE, selected);
    }
    renderer_.text(L"↑↓ Choose     Enter Select     Escape Resume", panelX + 35, panelY + panelHeight - 58,
                   panelWidth - 70, 30, 15, RGB(137, 149, 184), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

void Engine::drawChartEditor() {
    const int width = renderer_.width();
    const int height = renderer_.height();
    drawHeader(L"PRESS 7 IN GAME", L"CHART EDITOR", L"Editing " + widen(play_.song.title) + L" — saving is manual only.");

    const ChartEditorLayout layout = chartEditorLayout(width, height);
    const float gridX = layout.gridX;
    const float gridY = layout.gridY;
    const float gridWidth = layout.gridWidth;
    const float gridHeight = layout.gridHeight;
    const float laneWidth = layout.laneWidth;
    const float centerY = gridY + gridHeight * 0.5f;
    renderer_.rect(gridX, gridY, gridWidth, gridHeight, RGB(15, 18, 42), 22);
    renderer_.outline(gridX, gridY, gridWidth, gridHeight, RGB(57, 65, 105), 2, 22);

    const int selectedColumn = (editor_.player ? 4 : 0) + editor_.lane;
    renderer_.rect(gridX + selectedColumn * laneWidth + 3, gridY + 3, laneWidth - 6, gridHeight - 6,
                   mixColor(RGB(18, 21, 48), accent_, 0.13), 12);
    for (int lane = 1; lane < 8; ++lane) {
        renderer_.rect(gridX + lane * laneWidth, gridY + 8, 1, gridHeight - 16,
                       lane == 4 ? accent2_ : RGB(47, 53, 88));
    }
    renderer_.text(L"OPPONENT", gridX, gridY - 32, gridWidth * 0.5f, 28, 15, RGB(255, 130, 165),
                   DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(L"PLAYER", gridX + gridWidth * 0.5f, gridY - 32, gridWidth * 0.5f, 28, 15, accent_,
                   DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);

    const double visibleTime = 2500.0;
    for (const Note& note : editor_.chart.notes) {
        const double delta = note.timeMs - editor_.cursorTimeMs;
        if (std::abs(delta) > visibleTime) continue;
        const int column = (note.player ? 4 : 0) + note.lane;
        const float centerX = gridX + (column + 0.5f) * laneWidth;
        const float y = centerY - static_cast<float>(delta / visibleTime) * gridHeight * 0.5f;
        if (note.lengthMs > 0.0) {
            const float endY = y - static_cast<float>(note.lengthMs / visibleTime) * gridHeight * 0.5f;
            renderer_.rect(centerX - 4, endY, 8, std::max(3.0f, y - endY),
                           note.player ? accent_ : accent2_, 4);
        }
        const float noteSize = std::min(44.0f, laneWidth * 0.70f);
        renderer_.image(noteImagePath(root_, L"note", note.lane), centerX - noteSize * 0.5f,
                        y - noteSize * 0.5f, noteSize, noteSize);
    }
    renderer_.rect(gridX + 8, centerY - 2, gridWidth - 16, 4, RGB(255, 226, 92), 2);
    renderer_.text(std::to_wstring(static_cast<int>(std::round(editor_.cursorTimeMs))) + L" ms",
                   gridX + 12, centerY - 31, 140, 26, 14, RGB(255, 226, 92), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);

    const bool overGrid = pointInBox(mousePosition_, gridX, gridY, gridWidth, gridHeight);
    if (overGrid) {
        const int hoverColumn = std::clamp(static_cast<int>((mousePosition_.x - gridX) / laneWidth), 0, 7);
        renderer_.outline(gridX + hoverColumn * laneWidth + 4, gridY + 4, laneWidth - 8, gridHeight - 8,
                          RGB(255, 255, 255), 1, 10);
        renderer_.rect(gridX + 8, static_cast<float>(mousePosition_.y) - 1, gridWidth - 16, 2, RGB(200, 208, 235));
        renderer_.text(L"LEFT CLICK ADD  •  RIGHT CLICK DELETE", gridX + gridWidth - 330,
                       static_cast<float>(mousePosition_.y) - 28, 315, 24, 12, RGB(230, 234, 250),
                       DT_RIGHT | DT_VCENTER | DT_SINGLELINE, true);
    }

    const float panelX = layout.panelX;
    const float panelWidth = layout.panelWidth;
    renderer_.rect(panelX, gridY - 30, panelWidth, gridHeight + 30, RGB(20, 23, 52), 22);
    renderer_.outline(panelX, gridY - 30, panelWidth, gridHeight + 30, RGB(57, 65, 105), 2, 22);
    renderer_.text(editor_.dirty ? L"UNSAVED CHANGES" : L"SAVED / UNCHANGED", panelX + 22, gridY - 12,
                   panelWidth - 44, 30, 15, editor_.dirty ? RGB(255, 190, 75) : RGB(105, 225, 145),
                   DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text((editor_.player ? L"Owner: Player" : L"Owner: Opponent") +
                   (L"    Lane: " + std::to_wstring(editor_.lane + 1)),
                   panelX + 24, gridY + 30, panelWidth - 48, 30, 17, RGB(230, 233, 247),
                   DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(L"Hold: " + std::to_wstring(static_cast<int>(std::round(editor_.sustainMs))) + L" ms",
                   panelX + 24, gridY + 62, panelWidth - 48, 27, 15, RGB(158, 170, 205),
                   DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    const std::vector<std::wstring> actions{L"Add Note", L"Delete Nearest", L"Save Chart", L"Exit Without Saving"};
    const float actionsY = layout.actionsY;
    for (std::size_t index = 0; index < actions.size(); ++index) {
        const bool selected = static_cast<int>(index) == selection_;
        const float y = actionsY + static_cast<float>(index) * 54.0f;
        const bool hovered = pointInBox(mousePosition_, panelX + 20, y, panelWidth - 40, 44);
        COLORREF fill = selected || hovered ? mixColor(RGB(31, 35, 70), accent_, 0.30) : RGB(27, 31, 65);
        if (index == 2 && selected) fill = RGB(38, 118, 84);
        renderer_.rect(panelX + 20, y, panelWidth - 40, 44, fill, 13);
        if (selected || hovered) renderer_.outline(panelX + 20, y, panelWidth - 40, 44, index == 2 ? RGB(115, 245, 170) : accent_, 2, 13);
        renderer_.text(actions[index], panelX + 28, y, panelWidth - 56, 44, selected ? 19 : 17,
                       selected || hovered ? RGB(255, 255, 255) : RGB(160, 170, 202), DT_CENTER | DT_VCENTER | DT_SINGLELINE, selected || hovered);
    }

    renderer_.text(widen(editor_.status), panelX + 24, actionsY + 224, panelWidth - 48, 58, 14,
                   editor_.dirty ? RGB(255, 200, 100) : RGB(140, 210, 170), DT_CENTER | DT_WORDBREAK);
    renderer_.text(L"Mouse wheel scrolls   •   Left click adds   •   Right click deletes   •   Click Save Chart\nQ/E Time   ←/→ Lane   Tab Owner   A/D Hold   Esc Exit",
                   58, static_cast<float>(height - 88), static_cast<float>(width - 116), 60, 15, RGB(145, 157, 192),
                   DT_CENTER | DT_VCENTER | DT_WORDBREAK);
}

void Engine::drawResults() {
    drawHeader(L"SONG COMPLETE", L"RESULTS", widen(play_.song.title));
    const double accuracy = play_.judgedCount > 0 ? play_.accuracyPoints / play_.judgedCount : 0.0;
    std::wstring grade = accuracy >= 0.95 ? L"S" : accuracy >= 0.88 ? L"A" : accuracy >= 0.75 ? L"B" : accuracy >= 0.60 ? L"C" : L"D";
    renderer_.rect(64, 210, static_cast<float>(renderer_.width() - 128), 350, RGB(20, 23, 52), 28);
    renderer_.text(grade, 105, 245, 250, 230, 150, accent_, DT_CENTER | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.outline(115, 260, 230, 200, accent2_, 4, 55);
    const float x = 410;
    renderer_.text(L"Score", x, 245, 220, 30, 16, RGB(150,160,192));
    renderer_.text(std::to_wstring(play_.score), x, 275, 350, 52, 34, RGB(250,250,255), DT_LEFT | DT_VCENTER | DT_SINGLELINE, true);
    renderer_.text(L"Accuracy  " + percent(accuracy), x, 340, 330, 35, 20, RGB(220,224,240));
    renderer_.text(L"Max combo  " + std::to_wstring(play_.maxCombo), x, 380, 330, 35, 20, RGB(220,224,240));
    renderer_.text(L"Sick " + std::to_wstring(play_.ratings.sick) + L"    Good " + std::to_wstring(play_.ratings.good) + L"    Bad " + std::to_wstring(play_.ratings.bad) + L"    Miss " + std::to_wstring(play_.ratings.miss), x, 435, 650, 40, 18, accent2_);
    std::wstring action = L"Enter Continue";
    if (playingStory_) action = storyPosition_ + 1 < storyQueue_.size() ? L"Enter Next Song" : L"Enter Finish Week";
    renderer_.text(action, x, 495, 300, 35, 17, RGB(150,160,192));
}

} // namespace jave
