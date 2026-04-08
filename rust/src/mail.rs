use serde::Deserialize;

#[derive(Deserialize)]
pub struct Mail {
    pub id: i64,
    pub image_url: String,
    pub sender_id: String,
    pub approved: bool,
    pub created_at: String,
}
