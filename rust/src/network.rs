// lib.rs  (or network_message.rs)

use godot::{classes::{WebSocketPeer, web_socket_peer::State}, obj::NewGd, prelude::*};
use serde::Deserialize;

use crate::chatter::{Chatter, ChatterData}; // derive feature required in Cargo.toml

#[derive(GodotClass)]
#[class(base=Node)]
pub struct NetworkHandler {
    base: Base<Node>,
    socket: Gd<WebSocketPeer>
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
}

#[godot_api]
impl NetworkHandler {
    #[signal] fn emote_triggered(chatter: Gd<Chatter>, emote: GString);
    #[signal] fn scrolling_text_updated(text: GString);
    #[signal] fn pictionary_drawing_updated(svg: GString);

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

        match msg {
            WsMessage::TriggerEmote { chatter, emote } => {
                let chatter_obj: Gd<Chatter> = chatter.into();
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
        Self {
          base,
          socket: WebSocketPeer::new_gd()
        }
    }

    fn process(&mut self, _delta: f64) {
      self.socket.poll();
      match self.socket.get_ready_state() {
        State::CONNECTING => {

        }
        State::OPEN => {
          while self.socket.get_available_packet_count() > 0 {
            let packet = self.socket.get_packet();
            let message_str = packet.get_string_from_utf8();
            self.handle_packet(message_str);
          }
        }
        State::CLOSING => {
          
        }
        State::CLOSED => {
          
        }
        _ => {}
      }
    }
}
