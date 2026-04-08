use serde::Deserialize;

#[derive(Deserialize)]
pub struct ShopItemBase {
    pub tier: u32,
    pub price: f64,
    pub name: String,
    pub description: String,
    pub preview_scale: f64,
    pub model_center: [f64; 3],
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MeshType {
    Static,
    OwnSkeleton,
    SkinnedMesh,
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EquippedSlot {
    Headgear,
    RightHandItem,
    Tail,
    Arms,
    Torso,
    Legs,
}

#[derive(Deserialize)]
pub struct WearableMetadata {
    pub slot: EquippedSlot,
    pub mesh_type: MeshType,
    pub attach_to: Option<String>,
    pub offset: Option<[f64; 3]>,
    pub rotation: Option<[f64; 3]>,
    pub hide_meshes: Vec<String>,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum ShopItem {
    Wearable {
        #[serde(flatten)]
        base: ShopItemBase,
        metadata: WearableMetadata,
    },
    Emote {
        #[serde(flatten)]
        base: ShopItemBase,
        metadata: serde_json::Value,
    },
}
