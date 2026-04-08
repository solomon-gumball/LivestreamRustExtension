use godot::prelude::*;
use serde::Deserialize; // derive feature required in Cargo.toml

#[derive(Deserialize, Clone)]
pub struct EquippedData {
    headgear: Option<String>,
    right_hand_item: Option<String>,
    tail: Option<String>,
    arms: Option<String>,
    torso: Option<String>,
    legs: Option<String>,
}

#[derive(Deserialize, Clone)]
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
    equipped: EquippedData,
}

#[derive(GodotClass)]
#[class(base=RefCounted,init)]
pub struct Equipped {
    #[var] pub headgear: GString,
    #[var] pub right_hand_item: GString,
    #[var] pub tail: GString,
    #[var] pub arms: GString,
    #[var] pub torso: GString,
    #[var] pub legs: GString,
    base: Base<RefCounted>,
}

// impl IRefCounted for Equipped {

// }

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct Chatter {
    #[var] pub id: GString,
    #[var] pub display_name: GString,
    #[var] pub login: GString,
    #[var] pub created_at: GString,
    #[var] pub marbles_won: i64,
    #[var] pub duels_won: i64,
    #[var] pub royales_won: i64,
    #[var] pub gifts_given: i64,
    #[var] pub color: GString,
    #[var] pub emote: GString,
    #[var] pub balance: f64,
    #[var] pub last_active: GString,
    #[var] pub assets: Array<GString>,
    #[var] pub messages_sent: i64,
    #[var] pub followed_at: GString,
    #[var] pub equipped: Gd<Equipped>,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for Chatter {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            id: GString::new(),
            display_name: GString::new(),
            login: GString::new(),
            created_at: GString::new(),
            marbles_won: 0,
            duels_won: 0,
            royales_won: 0,
            gifts_given: 0,
            color: GString::new(),
            emote: GString::new(),
            balance: 0.0,
            last_active: GString::new(),
            assets: Array::new(),
            messages_sent: 0,
            followed_at: GString::new(),
            equipped: Equipped::new_gd(),
            base,
        }
    }
}

impl From<EquippedData> for Gd<Equipped> {
  fn from(data: EquippedData) -> Self {
    Gd::from_init_fn(|base| Equipped {
      headgear: data.headgear.as_deref().unwrap_or("").into(),
      right_hand_item: data.right_hand_item.as_deref().unwrap_or("").into(),
      tail: data.tail.as_deref().unwrap_or("").into(),
      arms: data.arms.as_deref().unwrap_or("").into(),
      torso: data.torso.as_deref().unwrap_or("").into(),
      legs: data.legs.as_deref().unwrap_or("").into(),
      base: base,
    })
  }
}

// impl From<Array<GString>> for Vec<String> {

// }

impl From<ChatterData> for Gd<Chatter> {
    fn from(data: ChatterData) -> Self {
        let assets = data.assets.iter()
            .map(|s| GString::from(s.as_str()))
            .collect::<Array<GString>>();

        Gd::from_init_fn(|base| Chatter {
            id: data.id.as_str().into(),
            display_name: data.display_name.as_str().into(),
            login: data.login.as_str().into(),
            created_at: data.created_at.as_str().into(),
            marbles_won: data.marbles_won as i64,
            duels_won: data.duels_won as i64,
            royales_won: data.royales_won as i64,
            gifts_given: data.gifts_given as i64,
            color: data.color.as_str().into(),
            emote: data.emote.as_str().into(),
            balance: data.balance,
            last_active: data.last_active.as_str().into(),
            assets,
            messages_sent: data.messages_sent as i64,
            followed_at: data.followed_at.as_deref().unwrap_or("").into(),
            equipped: data.equipped.into(),
            base,
        })
    }
}