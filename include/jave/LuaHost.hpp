#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

struct lua_State;

namespace jave {

class LuaHost {
public:
    using LogFn = std::function<void(const std::string&)>;
    using AccentFn = std::function<void(int, int, int)>;
    using PlayerFlipFn = std::function<void(bool)>;

    LuaHost();
    ~LuaHost();
    LuaHost(const LuaHost&) = delete;
    LuaHost& operator=(const LuaHost&) = delete;

    bool initialize(LogFn log, AccentFn accent, PlayerFlipFn playerFlip);
    void loadScripts(const std::filesystem::path& root, const std::vector<std::filesystem::path>& modRoots);
    void update(double dt);
    void songStart(const std::string& songId);
    void noteHit(int lane, const std::string& rating);
    [[nodiscard]] bool available() const;

private:
    void call(const char* function, int argumentCount);
    lua_State* state_{};
    LogFn log_;
    AccentFn accent_;
    PlayerFlipFn playerFlip_;
};

} // namespace jave
