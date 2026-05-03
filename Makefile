GODOT ?= godot
GODOT_PROJECT = godot

.PHONY: export extension-prod extension-local website-prod website-local overlay overlay-linux minigame build-rust export-games

export: extension-prod

extension-prod:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "extension_prod"

extension-local:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "extension_local"

website-prod:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-release "website_prod"
	gzip -f ../livestream-listener/public/index.wasm

website-local:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "website_local"

overlay:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "overlay"

minigame:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "minigame" "../../livestream-listener/public/games/pong.html"

export-games:
	bash export_games.sh $(GAME)

EMSDK_SYSROOT = $(HOME)/emsdk/upstream/emscripten/cache/sysroot
BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten = -isysroot $(EMSDK_SYSROOT) -I$(EMSDK_SYSROOT)/include

build-rust:
	cd rust && cargo +nightly build
	cd rust && BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="$(BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten)" cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten
