# Third-party notices

## Godot build

- **Godot Engine** 4.7, MIT license. Exported builds contain the Godot runtime. Notice: [licenses/GODOT-LICENSE.txt](licenses/GODOT-LICENSE.txt). Godot's own third-party components are listed in its `COPYRIGHT.txt` and returned by `Engine.get_copyright_info()`.
- **lua-gdextension** 0.8.2 by Gil Barbosa Reis, MIT license, vendored in `godot/addons/lua-gdextension/`. Notice: [godot/addons/lua-gdextension/LICENSE](godot/addons/lua-gdextension/LICENSE).
- **Lua** 5.4.8, built into lua-gdextension. Copyright © 1994–2025 Lua.org, PUC-Rio, MIT license. Notice: [licenses/LUA-LICENSE.txt](licenses/LUA-LICENSE.txt).
- **godot-cpp**, linked into lua-gdextension (a separate static library on iOS). MIT license, Godot Engine contributors; <https://github.com/godotengine/godot-cpp>.

Exports do not copy these files automatically; include them, together with `LICENSE`, when distributing a build.

## C++ reference build

- **Lua** 5.4.8, downloaded from <https://www.lua.org/> and statically linked when `JAVE_ENABLE_LUA=ON`. Notice: [licenses/LUA-LICENSE.txt](licenses/LUA-LICENSE.txt).
- If a Windows build made with LLVM-MinGW is distributed with LLVM runtime DLLs, those DLLs are under the Apache License 2.0 with LLVM Exceptions. Notice: [licenses/LLVM-LICENSE.txt](licenses/LLVM-LICENSE.txt). The repository contains no such DLLs.

## Project content

The Jave Engine source is covered by [LICENSE](LICENSE). The Neon Steps demo song, chart, stage and `assets/demo/` graphics are made for this project and dedicated under CC0 ([licenses/DEMO.txt](licenses/DEMO.txt)). Media imported by the user keeps its authors' rights and credits; check them before redistributing anything that contains it.
