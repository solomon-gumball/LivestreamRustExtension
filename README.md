# Livestream Rust Extension

## Setup

### Godot

Add the Godot binary to your `$PATH` so it can be invoked as `godot` from the terminal and Makefile.

Example:
```sh
sudo ln -s /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot
```

### Rust (godot-rust `api-custom` feature)

The `api-custom` feature requires the `GDRUST_GODOT_BIN` environment variable to point to the Godot binary so it can generate bindings at build time.

Add this to your `~/.zshrc`:

```sh
export GDRUST_GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
```

Then reload your shell:

```sh
source ~/.zshrc
```

### Localhost Certificates

The local dev server requires SSL certificates to serve the game over HTTPS. Add `localhost.pem` and `localhost-key.pem` to the `web/` directory.

You can generate them with [mkcert](https://github.com/FiloSottile/mkcert):

```sh
mkcert localhost
mv localhost.pem localhost-key.pem web/
```

## Building

```sh
make export
```

This will build the Rust library targeting `wasm32-unknown-emscripten` and then export the Godot project to `web/public/`.
