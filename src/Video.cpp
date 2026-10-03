#include "jave/Video.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <mfplay.h>

namespace jave {
namespace {
struct Events {
    std::atomic<bool> ready{false}, started{false}, ended{false};
    std::atomic<HRESULT> error{S_OK};
};

// Callbacks hold shared event state, never a raw Engine/VideoPlayer pointer.
// A callback racing with Shutdown therefore cannot access a destroyed engine.
class Callback final : public IMFPMediaPlayerCallback {
public:
    explicit Callback(std::shared_ptr<Events> events) : events_(std::move(events)) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (iid == __uuidof(IUnknown) || iid == __uuidof(IMFPMediaPlayerCallback)) {
            *result = static_cast<IMFPMediaPlayerCallback*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    void STDMETHODCALLTYPE OnMediaPlayerEvent(MFP_EVENT_HEADER* event) override {
        if (!event) return;
        if (FAILED(event->hrEvent)) {
            events_->error = event->hrEvent;
            events_->ended = true;
        } else if (event->eEventType == MFP_EVENT_TYPE_MEDIAITEM_SET) events_->ready = true;
        else if (event->eEventType == MFP_EVENT_TYPE_PLAY) events_->started = true;
        else if (event->eEventType == MFP_EVENT_TYPE_PLAYBACK_ENDED) events_->ended = true;
        else if (event->eEventType == MFP_EVENT_TYPE_ERROR) {
            events_->error = E_FAIL;
            events_->ended = true;
        }
    }
private:
    std::atomic<ULONG> references_{1};
    std::shared_ptr<Events> events_;
};
} // namespace

struct VideoPlayer::Impl {
    IMFPMediaPlayer* player{};
    HWND child{};
    HMODULE library{};
    bool comInitialized{};
    int width{}, height{}, x{}, y{};
    std::shared_ptr<Events> events = std::make_shared<Events>();
    std::chrono::steady_clock::time_point opened{};
};

VideoPlayer::VideoPlayer() : impl_(std::make_unique<Impl>()) {}
VideoPlayer::~VideoPlayer() {
    stop();
    // Keep the optional Windows library loaded for outstanding COM callbacks.
    if (impl_->comInitialized) CoUninitialize();
}

bool VideoPlayer::start(HWND parent, const std::filesystem::path& path, double volume) {
    stop();
    auto& state = *impl_;
    state.events = std::make_shared<Events>();
    const auto fail = [&](HRESULT result) {
        state.events->error = result;
        state.events->ended = true;
        stop();
        return false;
    };
    std::error_code fileError;
    if (!IsWindow(parent) || !std::filesystem::is_regular_file(path, fileError)) return fail(E_INVALIDARG);
    if (!state.comInitialized) {
        const HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(result) && result != RPC_E_CHANGED_MODE) return fail(result);
        state.comInitialized = SUCCEEDED(result);
    }
    // Dynamic loading allows builds to run without Media Feature Pack; a missing
    // video backend skips the scene safely instead of preventing engine startup.
    if (!state.library) state.library = LoadLibraryW(L"mfplay.dll");
    if (!state.library) return fail(HRESULT_FROM_WIN32(GetLastError()));
    using CreatePlayer = HRESULT (WINAPI*)(LPCWSTR, BOOL, MFP_CREATION_OPTIONS,
                                          IMFPMediaPlayerCallback*, HWND, IMFPMediaPlayer**);
    const auto create = reinterpret_cast<CreatePlayer>(GetProcAddress(state.library, "MFPCreateMediaPlayer"));
    if (!create) return fail(E_NOTIMPL);
    state.child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                                 0, 0, 1, 1, parent, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!state.child) return fail(HRESULT_FROM_WIN32(GetLastError()));
    auto* callback = new Callback(state.events);
    state.opened = std::chrono::steady_clock::now();
    const HRESULT result = create(path.c_str(), FALSE, MFP_OPTION_FREE_THREADED_CALLBACK,
                                  callback, state.child, &state.player);
    callback->Release();
    if (FAILED(result)) return fail(result);
    state.player->SetBorderColor(RGB(0, 0, 0));
    state.player->SetVolume(static_cast<float>(std::clamp(volume, 0.0, 1.0)));
    RECT client{};
    GetClientRect(parent, &client);
    resize(client.right, client.bottom - 34);
    SetFocus(parent);
    return true;
}

void VideoPlayer::stop() {
    auto& state = *impl_;
    if (state.player) {
        state.player->Shutdown();
        state.player->Release();
        state.player = nullptr;
    }
    if (state.child) { DestroyWindow(state.child); state.child = nullptr; }
    state.width = state.height = 0;
}

void VideoPlayer::update() {
    auto& state = *impl_;
    if (!state.player) return;
    if (state.events->ready.exchange(false) && !state.events->ended) {
        const HRESULT result = state.player->Play();
        if (FAILED(result)) { state.events->error = result; state.events->ended = true; }
    }
    if (!state.events->started && !state.events->ended &&
        std::chrono::steady_clock::now() - state.opened > std::chrono::seconds(15)) {
        state.events->error = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
        state.events->ended = true;
    }
}

void VideoPlayer::resize(int width, int height, int x, int y) {
    auto& state = *impl_;
    width = std::max(1, width); height = std::max(1, height);
    if (!state.child || (state.width == width && state.height == height && state.x == x && state.y == y)) return;
    state.width = width; state.height = height;
    state.x = x; state.y = y;
    MoveWindow(state.child, x, y, width, height, TRUE);
    repaint();
}
void VideoPlayer::repaint() { if (impl_->player) impl_->player->UpdateVideo(); }
bool VideoPlayer::started() const { return impl_->events->started; }
bool VideoPlayer::finished() const { return impl_->events->ended; }
HRESULT VideoPlayer::error() const { return impl_->events->error; }
double VideoPlayer::positionMs() const {
    if (!impl_->player) return 0;
    PROPVARIANT position{};
    const HRESULT result = impl_->player->GetPosition(MFP_POSITIONTYPE_100NS, &position);
    const double ms = SUCCEEDED(result) && position.vt == VT_I8 ? position.hVal.QuadPart / 10000.0 : 0;
    PropVariantClear(&position);
    return ms;
}
} // namespace jave
