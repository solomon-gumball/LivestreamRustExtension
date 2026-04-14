use godot::prelude::*;

struct MyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}

mod player;
mod network;
mod multiplayer_session;
mod chatter;
mod mail;
mod shop;