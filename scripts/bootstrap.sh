#!/bin/zsh
# One-time setup on a fresh clone: web dependencies, extension scripts, Xcode project.
source ${0:A:h}/lib.sh

step "Installing web dependencies"
pnpm --dir $ROOT/web install --frozen-lockfile

step "Building extension scripts"
pnpm --dir $ROOT/web build

step "Generating Prefill.xcodeproj"
xcodegen generate --spec $ROOT/project.yml --project $ROOT
