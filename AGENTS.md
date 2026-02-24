# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

This repository contains REAPER DAW Lua extension scripts (ReaScripts) distributed via ReaPack. There are two scripts:

- **Frenkie Item Properties** — GUI widget for item/take/track properties inside REAPER (uses `gfx.*` API)
- **Frenkie Recent Projects** — Recent projects manager widget (uses ReaImGui)

Scripts run exclusively inside REAPER's Lua scripting engine and depend on runtime globals (`reaper`, `gfx`). They cannot be executed standalone.

### Development tooling

| Task | Command |
|------|---------|
| Syntax check (all files) | `find /workspace -name '*.lua' -exec lua5.3 -e "local f=io.open('{}','r'); local c=f:read('*a'); f:close(); local ok,err=load(c,'{}'); if ok then print('OK: {}') else print('FAIL: {} -- '..err) end" \;` |
| Lint (all files) | `luacheck "Mr. Frenkie/" --std lua53 --globals reaper gfx` |
| Validate ReaPack index | `xmllint --noout index.xml` |

### Important caveats

- **No automated tests** exist in this repository. Validation is limited to syntax checking, linting, and XML validation.
- **No build step** — scripts are plain Lua loaded via `dofile()`.
- **Runtime testing requires REAPER** installed with ReaPack and ReaImGui extensions. This cannot be done in a headless cloud environment.
- Luacheck will report many warnings about undefined globals — these are REAPER API functions injected at runtime (e.g., `reaper.*`, `gfx.*`, and ImGui constants). Only `0 errors` matters; warnings are expected.
- File paths contain spaces (e.g., `Mr. Frenkie/Scripts/`). Always quote paths in shell commands.
