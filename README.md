# Livestream Rust Extension

## Setup

### Godot

Add the Godot binary to your `$PATH` so it can be invoked as `godot` from the terminal and Makefile.

Example:
```sh
sudo ln -s ~/godot/Godot_v4.6.2-stable_linux.x86_64 /user/local/bin
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

To run the `make export` script that exports the web project to the web/public dir, you should:
- Make sure you have downloaded the web export templates in the Editor (Project > Export)
- Install a nightly build of rustc:
```sh
rustup toolchain install nightly
rustup component add rust-src --toolchain nightly
rustup target add wasm32-unknown-emscripten --toolchain nightly

```
- Install Emscripten
```sh
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 3.1.74
./emsdk activate 3.1.74

source ./emsdk_env.sh  # on Linux
run ./emsdk_env.bat    # on Windows
```

Now you should be able to run the export script

```sh
make export
```


This will build the Rust library targeting `wasm32-unknown-emscripten` and then export the Godot project to `web/public/`.
