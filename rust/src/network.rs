// lib.rs  (or network_message.rs)

use std::collections::HashMap;

use godot::{classes::{WebSocketPeer, web_socket_peer::State}, obj::NewGd, prelude::*};
use serde::Deserialize;

use crate::{chatter::{Chatter, ChatterData}, shop::CommonShopTraits};
use crate::mail::Mail;
use crate::shop::ShopItem;

#[derive(GodotClass)]
#[class(base=Node)]
pub struct NetworkHandler {
    base: Base<Node>,
    socket: Gd<WebSocketPeer>,
    #[var] pub use_local_server: bool,
    item_info: HashMap<String, ShopItem>,
}

#[derive(Deserialize)]
pub struct DropData {
    coins: u32,
    stacks: u32,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum WsMessage {
    UpdateChatter { chatter: ChatterData },
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

    fn get_server_domain(&self) -> String {
        // In production, this would return the actual server domain, but for testing we can use localhost
        // return "livestream-listener-913887936892.us-central1.run.app".to_string();
        return
            if self.use_local_server { "localhost:1235".to_string() }
            else { "livestream-listener-913887936892.us-central1.run.app".to_string() };
    }

    #[func]
    fn get_database_server_url(&self) -> String {
        let protocol = if self.use_local_server { "http" } else { "https" };
        return format!("{}://{}", protocol, self.get_server_domain());
    }

    #[func]
    fn get_ws_url(&self) -> String {
        let protocol = if self.use_local_server { "ws" } else { "wss" };
        return format!("{}://{}", protocol, self.get_server_domain());
    }

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
    fn get_item_info(&self, item_name: GString) -> Variant {
        self.item_info.get(&item_name.to_string())
            .map(|item| {
                godot_print!("item found? {}", item.common().name);
                item.clone().into()
            })
            .unwrap_or(Variant::nil())
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
              godot_print!("Received chatter data for chatter {}", chatter.login);
              let chatter_obj: Gd<Chatter> = chatter.into();

              self.signals().chatter_updated().emit(&chatter_obj)
            }
            WsMessage::ShowMail { .. } => {}
            WsMessage::MailQueueUpdated { .. } => {}
            WsMessage::ImageTest { .. } => {}
            WsMessage::ItemInfo { info } => {
                self.item_info.extend(info);
            }
            WsMessage::ShopUpdated { .. } => {}
            WsMessage::ActionQueueUpdated { .. } => {}
            WsMessage::LeaderboardUpdated { .. } => {}
            WsMessage::RequestActivityAdvance => {}
            WsMessage::StoreData { active_chatters, market, .. } => {
              if let Some(chatter) = active_chatters.first() {
                let chatter_obj: Gd<Chatter> = chatter.clone().into();
                self.signals().chatter_updated().emit(&chatter_obj);
              }
              godot_print!("Received store data {}", json);
              market.iter().for_each(|item: &ShopItem| {
                self.item_info.insert(item.common().name.clone(), item.clone());
              });
            //   self.item_info = market.into_iter().map(|item| (item.name.clone(), item)).collect();
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
          use_local_server: true,
          socket: WebSocketPeer::new_gd(),
          item_info: HashMap::new(),
        }
    }

    fn ready(&mut self) {
        self.connect_to_server(&self.get_ws_url());
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
