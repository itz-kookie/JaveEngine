#pragma once

#include "jave/Json.hpp"

#include <array>
#include <filesystem>
#include <string>
#include <vector>

namespace jave {

struct Note {
    double timeMs{};
    int lane{};
    double lengthMs{};
    bool player{true};
    bool headHit{};
    bool holding{};
    double holdReleaseMs{};
    bool judged{};
    bool hit{};
};

struct CameraEvent {
    double timeMs{};
    std::string type;
    std::string target;
    double x{};
    double y{};
    double amount{};
};

struct Chart {
    std::string songId;
    std::string difficulty{"normal"};
    double bpm{120.0};
    double offsetMs{};
    std::vector<Note> notes;
    std::vector<CameraEvent> cameraEvents;
    double durationMs{};
};

struct Song {
    std::string id;
    std::string title;
    std::string artist;
    std::string description;
    std::string license;
    double bpm{120.0};
    int order{100000};
    std::string weekId;
    std::string stage{"stage"};
    std::string playerCharacter{"bf"};
    std::string opponentCharacter{"dad"};
    std::string girlfriendCharacter{"gf"};
    std::filesystem::path packageRoot;
    std::filesystem::path audioPath;
    std::filesystem::path chartPath;
    std::filesystem::path stageImage;
    std::filesystem::path playerVisual;
    std::filesystem::path opponentVisual;
    std::filesystem::path girlfriendVisual;
    std::filesystem::path playerIcon;
    std::filesystem::path opponentIcon;
    std::array<double, 2> playerPosition{770.0, 100.0};
    std::array<double, 2> opponentPosition{100.0, 100.0};
    std::array<double, 2> girlfriendPosition{400.0, 130.0};
    std::array<double, 2> cameraPlayer{0.0, 0.0};
    std::array<double, 2> cameraOpponent{0.0, 0.0};
    std::array<double, 2> cameraGirlfriend{0.0, 0.0};
    double stageZoom{0.9};
    double cameraSpeed{1.0};
    bool hideGirlfriend{};
    Json stageLayout;
    std::filesystem::path stageConfigPath;
};

struct Week {
    std::string id;
    std::string name;
    std::string storyName;
    std::vector<std::string> songIds;
    std::array<int, 3> color{95, 227, 255};
    std::filesystem::path packageRoot;
};

struct ModInfo {
    std::string id;
    std::string name;
    std::string version;
    std::string author;
    std::string description;
    int order{};
    bool enabled{true};
    std::filesystem::path root;
};

struct Settings {
    double masterVolume{0.8};
    double noteSpeed{1.0};
    bool downscroll{};
    bool fullscreen{};
    bool showFps{true};
    std::array<int, 4> keybinds{0x44, 0x46, 0x4A, 0x4B}; // D F J K
};

// Texture-backend-neutral animation state for mods and future renderers.
struct SpriteFrame { int x{}, y{}, width{}, height{}; double durationMs{100.0}; };
struct SpriteAnimation {
    std::string name;
    std::vector<SpriteFrame> frames;
    bool looping{true};
    std::size_t currentFrame{};
    double elapsedMs{};
    bool playing{true};
    void update(double deltaMs);
    void reset();
};

class ContentLibrary {
public:
    explicit ContentLibrary(std::filesystem::path root);

    void scan();
    void toggleMod(std::size_t index);
    [[nodiscard]] Chart loadChart(const Song& song) const;
    void reloadStage(Song& song) const;
    [[nodiscard]] const std::vector<Song>& songs() const { return songs_; }
    [[nodiscard]] const std::vector<Week>& weeks() const { return weeks_; }
    [[nodiscard]] const std::vector<ModInfo>& mods() const { return mods_; }
    [[nodiscard]] const Song* findSong(std::string_view id) const;
    [[nodiscard]] const Song* findWeekSong(const Week& week, std::string_view id) const;
    [[nodiscard]] std::filesystem::path assetPath(const std::filesystem::path& relative) const;
    [[nodiscard]] std::filesystem::path cutscenePath(const Song& song, bool outro) const;
    [[nodiscard]] const std::filesystem::path& root() const { return root_; }

    static Settings loadSettings(const std::filesystem::path& root);
    static void saveSettings(const std::filesystem::path& root, const Settings& settings);

private:
    std::filesystem::path root_;
    std::vector<Song> songs_;
    std::vector<Song> packageSongs_;
    std::vector<Week> weeks_;
    std::vector<ModInfo> mods_;
};

} // namespace jave
