#!/bin/bash
#
#
asdf plugin remove zig
asdf plugin add zig https://github.com/liyu1981/asdf-zig.git

mkdir -p ~/.asdf/custom/zig
echo "{\"0.12.0-dev.3666+a2b834e8c\": {}}" > ~/.asdf/custom/zig/versions.json

asdf install zig 0.12.0-dev.3666+a2b834e8c
asdf local use zig 0.12.0-dev.3666+a2b834e8c

zig fetch --save=sdl https://github.com/MasterQ32/SDL.zig/archive/55caabf.tar.gz
