// lib.rs  (or network_message.rs)

use godot::prelude::*;
use serde::Deserialize; // derive feature required in Cargo.toml

// ── 1. Deserializable Rust structs (serde) ────────────────────────────────────

#[derive(Deserialize)]
struct ChatterData {
    id: String,
    display_name: String,
    login: String,
    color: String,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum WsMessage {
    TriggerEmote {
        chatter: ChatterData,
        emote: String,
    },
    ScrollingTextUpdated {
        text: String,
    },
    PictionaryDrawingUpdated {
        svg: String,
    },
    // add more variants to match your message.type strings
}

// ── 2. A GDScript-visible class that holds the parsed data ────────────────────

/// Mirrors your GDScript `Chatter` class so GDScript can read the fields.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct Chatter {
    #[var] pub id: GString,
    #[var] pub display_name: GString,
    #[var] pub login: GString,
    #[var] pub color: GString,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for Chatter {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            id: GString::new(),
            display_name: GString::new(),
            login: GString::new(),
            color: GString::new(),
            base,
        }
    }
}

impl Chatter {
    fn from_data(data: ChatterData) -> Gd<Self> {
        Gd::from_init_fn(|base| Self {
            id: data.id.as_str().into(),
            display_name: data.display_name.as_str().into(),
            login: data.login.as_str().into(),
            color: data.color.as_str().into(),
            base,
        })
    }
}

// ── 3. The WebSocket handler node exposed to GDScript ─────────────────────────

#[derive(GodotClass)]
#[class(base=Node)]
pub struct NetworkHandler {
    base: Base<Node>,
}

/// Signals GDScript connects to — same names as your existing ones.
#[godot_api]
impl NetworkHandler {
    #[signal]
    fn emote_triggered(chatter: Gd<Chatter>, emote: GString);

    #[signal]
    fn scrolling_text_updated(text: GString);

    #[signal]
    fn pictionary_drawing_updated(svg: GString);

    /// Call this from GDScript when a raw packet arrives, e.g.:
    ///   handler.handle_packet(packet.get_string_from_utf8())
    #[func]
    fn handle_packet(&mut self, raw: GString) {
        let json = raw.to_string();

        let msg: WsMessage = match serde_json::from_str(&json) {
            Ok(m) => m,
            Err(e) => {
                godot_error!("Failed to parse WS message: {e}");
                return;
            }
        };

        // mirrors your GDScript `match message.type:` block
        match msg {
            WsMessage::TriggerEmote { chatter, emote } => {
                let chatter_obj = Chatter::from_data(chatter);
                self.signals().emote_triggered().emit(&chatter_obj, &GString::from(&emote));
            }
            WsMessage::ScrollingTextUpdated { text } => {
              self.signals().scrolling_text_updated().emit(&GString::from(&text));
            }
            WsMessage::PictionaryDrawingUpdated { svg } => {
                self.signals().pictionary_drawing_updated().emit(&GString::from(&svg));
            }
        }
    }
}

#[godot_api]
impl INode for NetworkHandler {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}
