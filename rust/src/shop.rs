use godot::prelude::*;
use serde::Deserialize;

fn arr3_to_vec3(v: [f64; 3]) -> Vector3 {
    Vector3::new(v[0] as f32, v[1] as f32, v[2] as f32)
}

// GODOT CLASSES

#[derive(Deserialize, Clone)]
pub struct ShopItemCommon {
    pub tier: u32,
    pub price: f64,
    pub name: String,
    pub description: String,
    pub preview_scale: f64,
    pub model_center: [f64; 3]
}

#[derive(Deserialize, Clone)]
pub struct WearableMetadata {
    pub slot: EquippedSlot,
    pub mesh_type: MeshType,
    pub attach_to: Option<String>,
    pub offset: Option<[f64; 3]>,
    pub rotation: Option<[f64; 3]>,
    pub hide_meshes: Vec<String>,
}

#[derive(Deserialize, Clone)]
pub enum ShopItem {
    Wearable {
        #[serde(flatten)]
        metadata: WearableMetadata,
        common: ShopItemCommon,
    },
    Emote {
        #[serde(flatten)]
        metadata: serde_json::Value,
        common: ShopItemCommon,
    },
}
trait CommonShopTraits {
    fn common(&self) -> &ShopItemCommon;
}
impl CommonShopTraits for ShopItem {
    fn common(&self) -> &ShopItemCommon {
        match self {
            ShopItem::Wearable { common, .. } => common,
            ShopItem::Emote { common, .. } => common,
        }
    }
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "snake_case")]
pub enum MeshType {
    Static,
    OwnSkeleton,
    SkinnedMesh,
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "snake_case")]
pub enum EquippedSlot {
    Headgear,
    RightHandItem,
    Tail,
    Arms,
    Torso,
    Legs,
}

// --- Godot-exposed classes ---

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct WearableItemMetadata {
    #[var] pub slot: GString,
    #[var] pub mesh_type: GString,
    #[var] pub offset: Vector3,
    #[var] pub rotation: Vector3,
    #[var] pub attach_to: GString,
    #[var] pub hide_meshes: Array<GString>,
    base: Base<RefCounted>,
}

impl From<WearableMetadata> for Gd<WearableItemMetadata> {
    fn from(data: WearableMetadata) -> Self {
        let slot: GString = match data.slot {
            EquippedSlot::Headgear => "headgear",
            EquippedSlot::RightHandItem => "right_hand_item",
            EquippedSlot::Tail => "tail",
            EquippedSlot::Arms => "arms",
            EquippedSlot::Torso => "torso",
            EquippedSlot::Legs => "legs",
        }.into();
        let mesh_type: GString = match data.mesh_type {
            MeshType::Static => "static",
            MeshType::OwnSkeleton => "own_skeleton",
            MeshType::SkinnedMesh => "skinned_mesh",
        }.into();
        let hide_meshes = data.hide_meshes.iter()
            .map(|s| GString::from(s.as_str()))
            .collect::<Array<GString>>();
        Gd::from_init_fn(|base| WearableItemMetadata {
            slot,
            mesh_type,
            offset: data.offset.map(arr3_to_vec3).unwrap_or_default(),
            rotation: data.rotation.map(arr3_to_vec3).unwrap_or_default(),
            attach_to: data.attach_to.as_deref().unwrap_or("").into(),
            hide_meshes,
            base,
        })
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct WearableShopItem {
    #[var] pub price: f64,
    #[var] pub name: GString,
    #[var] pub description: GString,
    #[var] pub tier: i64,
    #[var] pub preview_scale: f64,
    #[var] pub model_center: Vector3,
    #[var] pub metadata: Gd<WearableItemMetadata>,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for WearableShopItem {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            price: 0.0,
            name: GString::new(),
            description: GString::new(),
            tier: 0,
            preview_scale: 1.0,
            model_center: Vector3::ZERO,
            metadata: WearableItemMetadata::new_gd(),
            base,
        }
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct EmoteShopItem {
    #[var] pub price: f64,
    #[var] pub name: GString,
    #[var] pub description: GString,
    #[var] pub tier: i64,
    #[var] pub preview_scale: f64,
    #[var] pub model_center: Vector3,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for EmoteShopItem {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            price: 0.0,
            name: GString::new(),
            description: GString::new(),
            tier: 0,
            preview_scale: 1.0,
            model_center: Vector3::ZERO,
            base,
        }
    }
}

impl From<ShopItem> for Variant {
    fn from(item: ShopItem) -> Self {

        match item {
            ShopItem::Wearable { common, metadata } => {
                Gd::from_init_fn(|gd_base| WearableShopItem {
                    price: base.price,
                    name: base.name.as_str().into(),
                    description: base.description.as_str().into(),
                    tier: base.tier as i64,
                    preview_scale: base.preview_scale,
                    model_center: arr3_to_vec3(base.model_center),
                    metadata: metadata.into(),
                    base: gd_base,
                }).to_variant()
            }
            ShopItem::Emote { base, .. } => {
                Gd::from_init_fn(|gd_base| EmoteShopItem {
                    price: base.price,
                    name: base.name.as_str().into(),
                    description: base.description.as_str().into(),
                    tier: base.tier as i64,
                    preview_scale: base.preview_scale,
                    model_center: arr3_to_vec3(base.model_center),
                    base: gd_base,
                }).to_variant()
            }
        }
    }
}
