GODOT ?= godot
GODOT_PROJECT = godot
EXPORT_PRESET = LivestreamRustExtension
EXPORT_PATH = ../web/public/index.html

.PHONY: export build-rust

export: build-rust
	$(GODOT) --headless --path $(GODOT_PROJECT) --export-debug "$(EXPORT_PRESET)" "$(EXPORT_PATH)"

build-rust:
	cd rust && cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten
