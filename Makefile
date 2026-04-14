GODOT ?= godot
GODOT_PROJECT = godot
EXPORT_PRESET = LivestreamRustExtension
EXPORT_PATH = ../web/public/index.html

.PHONY: export build-rust

# export: build-rust
export:
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "$(EXPORT_PRESET)" "$(EXPORT_PATH)"

EMSDK_SYSROOT = $(HOME)/emsdk/upstream/emscripten/cache/sysroot
BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten = -isysroot $(EMSDK_SYSROOT) -I$(EMSDK_SYSROOT)/include

build-rust:
	cd rust && cargo +nightly build
	cd rust && BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="$(BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten)" cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten
