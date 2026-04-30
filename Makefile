GODOT ?= godot
GODOT_PROJECT = godot

.PHONY: export extension-prod extension-local overlay overlay-linux minigame build-rust export-games

export: extension-prod

extension-prod:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "extension_prod" "../web/public/index.html"

extension-local:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "extension_local" "../web/public/index.html"

overlay:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "overlay" "../overlay/index.html"

overlay-linux:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "Linux" "../overlay/gumbots_overlay.x86_64"

minigame:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "minigame" "../../livestream-listener/public/games/pong.html"

export-games:
	bash export_games.sh $(GAME)

EMSDK_SYSROOT = $(HOME)/emsdk/upstream/emscripten/cache/sysroot
BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten = -isysroot $(EMSDK_SYSROOT) -I$(EMSDK_SYSROOT)/include

build-rust:
	cd rust && cargo +nightly build
	cd rust && BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="$(BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten)" cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten
