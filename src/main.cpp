#include "jave/Engine.hpp"

#include <exception>
#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    try {
        jave::Engine engine(instance);
        return engine.run();
    } catch (const std::exception& error) {
        const std::wstring message = jave::widen(error.what());
        MessageBoxW(nullptr, message.c_str(), L"Jave Engine - Fatal error", MB_OK | MB_ICONERROR);
        return 1;
    }
}
