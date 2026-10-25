# Lua

Lua 5.4.9 from https://www.lua.org/ftp/lua-5.4.9.tar.gz
(SHA-256 `2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6`), MIT license
(the notice is at the end of `src/lua.h`).

Only the core and the libraries scripts may use are kept: base, coroutine, string, table,
math and utf8. The standalone interpreters (`lua.c`, `luac.c`), `linit.c` and the libraries
that reach outside the sprite (`io`, `os`, `package`, `debug`) are left out, so scripts can't
read files, run programs or load native code.
