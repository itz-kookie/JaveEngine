#pragma once

#include <filesystem>
#include <memory>
#include <windows.h>

namespace jave {

// Windows decodes MP4 video/audio; no external video-player process is launched.
class VideoPlayer {
public:
    VideoPlayer();
    ~VideoPlayer();
    VideoPlayer(const VideoPlayer&) = delete;
    VideoPlayer& operator=(const VideoPlayer&) = delete;
    bool start(HWND parent, const std::filesystem::path& path, double volume);
    void stop();
    void update();
    void resize(int width, int height, int x = 0, int y = 0);
    void repaint();
    [[nodiscard]] bool started() const;
    [[nodiscard]] bool finished() const;
    [[nodiscard]] HRESULT error() const;
    [[nodiscard]] double positionMs() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace jave
