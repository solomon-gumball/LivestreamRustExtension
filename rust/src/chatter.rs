use godot::prelude::*;
use serde::Deserialize; // derive feature required in Cargo.toml

#[derive(Deserialize)]
pub struct Equipped {
    headgear: Option<String>,
    right_hand_item: Option<String>,
    tail: Option<String>,
    arms: Option<String>,
    torso: Option<String>,
    legs: Option<String>,
}

#[derive(Deserialize)]
pub struct ChatterData {
    id: String,
    display_name: String,
    login: String,
    created_at: String,
    marbles_won: u32,
    duels_won: u32,
    royales_won: u32,
    gifts_given: u32,
    color: String,
    emote: String,
    balance: f64,
    last_active: String,
    assets: Vec<String>,
    messages_sent: u32,
    followed_at: Option<String>,
    equipped: Equipped,
}

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
            base
        }
    }
}

impl From<ChatterData> for Gd<Chatter> {
  fn from(data: ChatterData) -> Self {
    Gd::from_init_fn(|base| Chatter {
      id: data.id.as_str().into(),
      display_name: data.display_name.as_str().into(),
      login: data.login.as_str().into(),
      color: data.color.as_str().into(),
      base,
    })
  }
}