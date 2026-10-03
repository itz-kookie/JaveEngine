#pragma once

#include "jave/Audio.hpp"
#include "jave/Content.hpp"
#include "jave/LuaHost.hpp"
#include "jave/Video.hpp"

#include <array>
#include <chrono>
#include <filesystem>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <vector>

#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>

namespace jave {

enum class Screen { Main, Story, Freeplay, Mods, Options, Credits, Playing, Paused, ChartEditor, Results, Cutscene };

struct InputState {
    std::array<bool, 256> down{};
    std::array<bool, 256> pressed{};
    void onKeyDown(unsigned key);
    void onKeyUp(unsigned key);
    void endFrame();
    [[nodiscard]] bool wasPressed(int key) const;
};

struct RatingStats { int sick{}, good{}, bad{}, miss{}; };

struct GameplayState {
    Chart chart;
    Song song;
    int score{};
    int combo{};
    int maxCombo{};
    int misses{};
    double health{0.5};
    double accuracyPoints{};
    int judgedCount{};
    RatingStats ratings;
    std::string lastRating;
    double ratingLife{};
    double songTimeMs{};
    double songEndMs{};
    double playerAnimationMs{};
    double opponentAnimationMs{};
    std::array<double, 4> opponentFlash{};
    std::array<double, 4> playerFlash{};
    int playerPose{-1};
    int opponentPose{-1};
    double playerPoseLife{};
    double opponentPoseLife{};
    std::size_t nextCameraEvent{};
    std::string cameraFocus{"opponent"};
    bool cameraForced{};
    double cameraManualX{};
    double cameraManualY{};
    double cameraPanX{};
    double cameraPanY{};
    double cameraZoomBase{0.9};
    double cameraZoomPulse{};
    bool botplay{};
    bool active{};
};

struct ChartEditorState {
    Chart chart;
    double cursorTimeMs{};
    int lane{};
    bool player{true};
    double sustainMs{};
    bool dirty{};
    std::string status{"No unsaved changes"};
};

// One logical game picture, uniformly enlarged to fit any client area.
struct RenderViewport {
    static constexpr int CanvasWidth = 1280;
    static constexpr int CanvasHeight = 720;
    int x{}, y{}, width{}, height{};
    static RenderViewport fit(int width, int height);
    [[nodiscard]] POINT toCanvas(POINT point) const;
};

class Renderer {
public:
    Renderer();
    ~Renderer();
    void resize(HWND window, int width, int height);
    void begin(HDC target, int width, int height);
    void end(HDC target, int outputWidth = 0, int outputHeight = 0);
    void clearGradient(COLORREF top, COLORREF bottom);
    void rect(float x, float y, float w, float h, COLORREF color, int radius = 0);
    void outline(float x, float y, float w, float h, COLORREF color, int thickness = 1, int radius = 0);
    void text(const std::wstring& value, float x, float y, float w, float h, int size,
              COLORREF color, UINT align = DT_LEFT | DT_VCENTER | DT_SINGLELINE, bool bold = false);
    void ellipse(float x, float y, float w, float h, COLORREF color);
    void polygon(const std::vector<POINT>& points, COLORREF fill, COLORREF border, int thickness = 2);
    void image(const std::filesystem::path& path, float x, float y, float w, float h,
               bool flipX = false, bool stretch = false);
    [[nodiscard]] int width() const { return width_; }
    [[nodiscard]] int height() const { return height_; }
private:
    HDC memory_{};
    HBITMAP bitmap_{};
    HBITMAP oldBitmap_{};
    int width_{};
    int height_{};
    ULONG_PTR gdiplusToken_{};
    std::unique_ptr<Gdiplus::Graphics> graphics_;
    std::map<std::wstring, std::unique_ptr<Gdiplus::Image>> images_;
    std::map<std::pair<int, bool>, HFONT> fonts_;
};

class Engine {
public:
    explicit Engine(HINSTANCE instance, std::filesystem::path dataRoot = {});
    int run();

private:
    static LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
    LRESULT handleMessage(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
    void updatePointer(HWND window, LPARAM position);
    bool createWindow();
    void update(double dt);
    void render();
    void switchScreen(Screen next);
    void menuInput(int itemCount);
    void startSong(const Song& song);
    void startStorySong(const Song& song);
    bool startCutscene(const Song& song, bool outro);
    void finishCutscene(bool cancelled = false);
    void restartSong();
    void pauseSong();
    void resumeSong();
    void openChartEditor();
    void closeChartEditor();
    void updateChartEditor();
    void addEditorNote();
    void deleteEditorNote();
    void saveChartEditor();
    void startWeek(const Week& week);
    void updateGameplay(double dt);
    void judgeLane(int lane);
    void finishSong();
    void toggleFullscreen();
    void log(const std::string& message);

    void drawBackdrop();
    float drawFunkinLabel(const std::wstring& value, float x, float y, float width, float height);
    void drawHeader(const std::wstring& eyebrow, const std::wstring& title, const std::wstring& subtitle = L"");
    void drawMenu(const std::vector<std::wstring>& items, float startY, float width = 430.0f);
    void drawMain();
    void drawStory();
    void drawFreeplay();
    void drawMods();
    void drawOptions();
    void drawCredits();
    void drawGameplay();
    void drawPause();
    void drawChartEditor();
    void drawResults();

    std::filesystem::path root_;
    HINSTANCE instance_{};
    HWND window_{};
    Renderer renderer_;
    InputState input_;
    ContentLibrary content_;
    Settings settings_;
    AudioPlayer audio_;
    VideoPlayer video_;
    LuaHost lua_;
    Screen screen_{Screen::Main};
    int selection_{};
    int previousSelection_{};
    double selectionTween_{};
    double globalTime_{};
    bool running_{true};
    bool rebinding_{};
    int rebindLane_{};
    GameplayState play_;
    ChartEditorState editor_;
    std::vector<const Song*> storyQueue_;
    std::size_t storyPosition_{};
    bool playingStory_{};
    Song cutsceneSong_;
    std::string cutsceneName_;
    bool cutsceneOutro_{};
    bool cutsceneStartedLogged_{};
    bool playerFlip_{};
    POINT mousePosition_{};
    bool mouseLeftPressed_{};
    bool mouseRightPressed_{};
    int mouseWheelDelta_{};
    COLORREF accent_{RGB(95, 227, 255)};
    COLORREF accent2_{RGB(255, 81, 170)};
    RECT windowedRect_{};
    DWORD windowedStyle_{};
    std::mt19937 random_{0x4A415645};
    double fps_{60.0};
    double fpsAccumulator_{};
    int fpsFrames_{};
};

std::wstring widen(const std::string& value);

} // namespace jave
