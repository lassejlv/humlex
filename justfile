set shell := ["zsh", "-cu"]

run:
    ./run.sh

build:
    swift build

build-release:
    swift build -c release

dmg version="1.0" arch=`uname -m`:
    ./build-dmg.sh {{version}} {{arch}}

clean:
    rm -rf .build/debug .build/release

clean-all:
    rm -rf .build

verify-sparkle:
    ./scripts/verify-sparkle-keypair.sh

skills *args:
    ./skills.sh {{args}}

skills-bootstrap repo="vercel-labs/agent-skills":
    ./skills.sh bootstrap {{repo}}

skills-list:
    ./skills.sh list

skills-check:
    ./skills.sh check

skills-update:
    ./skills.sh update
