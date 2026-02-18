set shell := ["zsh", "-cu"]

default:
    @just --list

build:
    swift build

build-release:
    swift build -c release

run:
    ./run.sh

dmg version="1.0" arch=`uname -m`:
    ./build-dmg.sh {{version}} {{arch}}

clean:
    rm -rf .build/debug .build/release

clean-all:
    rm -rf .build

verify-sparkle:
    ./scripts/verify-sparkle-keypair.sh
