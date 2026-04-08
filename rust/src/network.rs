// lib.rs  (or network_message.rs)

use std::collections::HashMap;

use godot::{classes::{WebSocketPeer, web_socket_peer::State}, obj::NewGd, prelude::*};
use serde::Deserialize;

use crate::chatter::{Chatter, ChatterData};
use crate::mail::Mail;
use crate::shop::ShopItem;

#[derive(GodotClass)]
#[class(base=Node)]
pub struct NetworkHandler {
    base: Base<Node>,
    socket: Gd<WebSocketPeer>
}

#[derive(Deserialize)]
pub struct DropData {
    coins: u32,
    stacks: u32,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum WsMessage {
    UpdateChatter { chatter: ChatterData},
    ShowMail {
        mail: Mail,
        chatter: ChatterData,
        uuid: String
    },
    MailQueueUpdated { mail: Vec<Mail> },
    ImageTest { base64: String },
    ItemInfo { info: std::collections::HashMap<String, ShopItem> },
    ShopUpdated { items: Vec<String> },
    ActionQueueUpdated { action_queue: Vec<WsMessage>},
    TriggerEmote {
        chatter: ChatterData,
        emote: String
    },
    ScrollingTextUpdated { text: String },
    PictionaryDrawingUpdated { svg: String },
    LeaderboardUpdated { leaderboard: Vec<ChatterData> },
    RequestActivityAdvance,
    StoreData {
        action_queue: Vec<Box<WsMessage>>,
        active_chatters: Vec<ChatterData>,
        market: Vec<ShopItem>,
        drops: DropData,
        scrolling_text: String,
        flags: HashMap<String, bool>
    }
}

#[godot_api]
impl NetworkHandler {
    #[signal] fn emote_triggered(chatter: Gd<Chatter>, emote: GString);
    #[signal] fn scrolling_text_updated(text: GString);
    #[signal] fn pictionary_drawing_updated(svg: GString);
    #[signal] fn chatter_updated(chatter: Gd<Chatter>);

    fn connect_to_server(&mut self, url: &str) {
        godot_print!("Connecting to WebSocket server at: {url}");
        let error = self.socket.connect_to_url(url);
        if error != godot::global::Error::OK {
            godot_error!("Failed to connect to WebSocket server: {error:?}");
        } else {
            godot_print!("Successfully connected to WebSocket server.");
        }
    }

    #[func]
    fn subscribe(&mut self, channels: Array<GString>) {
        let message_arr: Vec<String> = channels.iter_shared()
        .map(|c| c.to_string())
        .collect();

        let json_str = serde_json::json!({
          "type": "subscribe",
          "channels": message_arr
        });
        godot_print!("subscribe json -> {json_str}");
        self.socket.send_text(&json_str.to_string());
    }

    #[func]
    fn handle_packet(&mut self, raw: GString) {
        let json = raw.to_string();

        let msg: WsMessage = match serde_json::from_str(&json) {
            Ok(m) => m,
            Err(e) => {
                // godot_print!("{json}");
                // Do NOT log the json string here, if it's too big it can crash you pc!
                godot_error!("Failed to parse WS message: {e}");
                return;
            }
        };
        // godot_print!("Received WS message: {json}");

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
            WsMessage::UpdateChatter { chatter } => {
              let chatter_obj: Gd<Chatter> = chatter.into();
              self.signals().chatter_updated().emit(&chatter_obj)
            }
            WsMessage::ShowMail { .. } => {}
            WsMessage::MailQueueUpdated { .. } => {}
            WsMessage::ImageTest { .. } => {}
            WsMessage::ItemInfo { .. } => {}
            WsMessage::ShopUpdated { .. } => {}
            WsMessage::ActionQueueUpdated { .. } => {}
            WsMessage::LeaderboardUpdated { .. } => {}
            WsMessage::RequestActivityAdvance => {}
            WsMessage::StoreData { active_chatters, .. } => {
              if let Some(chatter) = active_chatters.first() {
                let chatter_obj: Gd<Chatter> = chatter.clone().into();
                self.signals().chatter_updated().emit(&chatter_obj);
              }
              self.subscribe(array!["SIMULATION"]);
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

    fn ready(&mut self) {
        // self.connect_to_server("wss://livestream-listener-913887936892.us-central1.run.app");
        self.connect_to_server("ws://localhost:1235");
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
