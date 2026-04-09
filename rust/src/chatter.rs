use godot::prelude::*;
use serde::Deserialize; // derive feature required in Cargo.toml

#[derive(Deserialize, Clone)]
pub struct EquippedData {
    pub headgear: Option<String>,
    pub right_hand_item: Option<String>,
    pub tail: Option<String>,
    pub arms: Option<String>,
    pub torso: Option<String>,
    pub legs: Option<String>,
}

#[derive(Deserialize, Clone)]
pub struct ChatterData {
    pub id: String,
    pub display_name: String,
    pub login: String,
    pub created_at: String,
    pub marbles_won: u32,
    pub duels_won: u32,
    pub royales_won: u32,
    pub gifts_given: u32,
    pub color: String,
    pub emote: String,
    pub balance: f64,
    pub last_active: String,
    pub assets: Vec<String>,
    pub messages_sent: u32,
    pub followed_at: Option<String>,
    pub equipped: EquippedData,
}

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
    #[var] pub equipped: Dictionary<GString, GString>,
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
            equipped: Dictionary::new(),
            base,
        }
    }
}

impl From<EquippedData> for Dictionary<GString, GString> {
    fn from(data: EquippedData) -> Self {
        let mut dict = Dictionary::new();
        dict.set("headgear", data.headgear.as_deref().unwrap_or(""));
        dict.set("right_hand_item", data.right_hand_item.as_deref().unwrap_or(""));
        dict.set("tail", data.tail.as_deref().unwrap_or(""));
        dict.set("arms", data.arms.as_deref().unwrap_or(""));
        dict.set("torso", data.torso.as_deref().unwrap_or(""));
        dict.set("legs", data.legs.as_deref().unwrap_or(""));
        dict
    }
}

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
