use godot::prelude::*;
use serde::Deserialize;

// ── Wire format (server → client) ───────────────────────────────────────────

/// Serde-deserialised form of every incoming RTC signalling message.
/// Kept separate from `RtcIncoming` so that the Godot-facing node is not
/// coupled to the serialisation layer.
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum RtcWsMessage {
    /// Server assigned us a peer ID and lobby mode.
    RtcPeerId { peer_id: i32, mesh_mode: bool },
    /// Lobby creation / join confirmed.
    RtcLobbyJoined { lobby_name: String },
    /// Another peer entered the lobby.
    RtcPeerConnected { peer_id: i32 },
    /// A peer left the lobby.
    RtcPeerDisconnected { peer_id: i32 },
    /// Relayed WebRTC offer from `from_peer_id`.
    RtcOffer { from_peer_id: i32, sdp: String },
    /// Relayed WebRTC answer from `from_peer_id`.
    RtcAnswer { from_peer_id: i32, sdp: String },
    /// Relayed ICE candidate from `from_peer_id`.
    RtcCandidate { from_peer_id: i32, candidate: String },
    /// Lobby sealed by host — no further joins allowed.
    RtcLobbySealed,
}

// ── Internal dispatch type ───────────────────────────────────────────────────

/// Parsed RTC event dispatched from `NetworkHandler` into this node.
pub enum RtcIncoming {
    PeerId { peer_id: i32, mesh_mode: bool },
    LobbyJoined { lobby_name: String },
    PeerConnected { peer_id: i32 },
    PeerDisconnected { peer_id: i32 },
    Offer { from_peer_id: i32, sdp: String },
    Answer { from_peer_id: i32, sdp: String },
    Candidate { from_peer_id: i32, candidate: String },
    LobbySealed,
}

impl From<RtcWsMessage> for RtcIncoming {
    fn from(msg: RtcWsMessage) -> Self {
        match msg {
            RtcWsMessage::RtcPeerId { peer_id, mesh_mode } =>
                RtcIncoming::PeerId { peer_id, mesh_mode },
            RtcWsMessage::RtcLobbyJoined { lobby_name } =>
                RtcIncoming::LobbyJoined { lobby_name },
            RtcWsMessage::RtcPeerConnected { peer_id } =>
                RtcIncoming::PeerConnected { peer_id },
            RtcWsMessage::RtcPeerDisconnected { peer_id } =>
                RtcIncoming::PeerDisconnected { peer_id },
            RtcWsMessage::RtcOffer { from_peer_id, sdp } =>
                RtcIncoming::Offer { from_peer_id, sdp },
            RtcWsMessage::RtcAnswer { from_peer_id, sdp } =>
                RtcIncoming::Answer { from_peer_id, sdp },
            RtcWsMessage::RtcCandidate { from_peer_id, candidate } =>
                RtcIncoming::Candidate { from_peer_id, candidate },
            RtcWsMessage::RtcLobbySealed =>
                RtcIncoming::LobbySealed,
        }
    }
}

// ── Godot node ───────────────────────────────────────────────────────────────

/// Child node of `NetworkHandler` that manages a WebRTC signalling session
/// over the shared WebSocket connection.
///
/// **Receiving:** `NetworkHandler.handle_packet` forwards any packet it cannot
/// parse as a `WsMessage` to this node by calling `handle_rtc_message`.
///
/// **Sending:** Outgoing messages are routed through `NetworkHandler.send_ws_text`
/// via Godot's dynamic dispatch, so this node needs no direct Rust reference to
/// its parent.
#[derive(GodotClass)]
#[class(base=Node)]
pub struct MultiplayerSessionHandler {
    base: Base<Node>,
}

#[godot_api]
impl MultiplayerSessionHandler {
    // ── Signals ──────────────────────────────────────────────────────────────

    /// Server assigned us a peer ID.  `use_mesh` indicates whether the lobby
    /// uses full mesh (true) or host-as-relay mode (false).
    #[signal]
    fn connected(peer_id: i32, use_mesh: bool);

    /// Lobby creation or join was confirmed by the server.
    #[signal]
    fn lobby_joined(lobby_name: GString);

    /// Another peer joined the lobby.
    #[signal]
    fn peer_connected(peer_id: i32);

    /// A peer left the lobby.
    #[signal]
    fn peer_disconnected(peer_id: i32);

    /// A WebRTC offer was relayed from `from_peer_id`.
    #[signal]
    fn offer_received(from_peer_id: i32, sdp: GString);

    /// A WebRTC answer was relayed from `from_peer_id`.
    #[signal]
    fn answer_received(from_peer_id: i32, sdp: GString);

    /// An ICE candidate was relayed from `from_peer_id`.
    #[signal]
    fn candidate_received(from_peer_id: i32, candidate: GString);

    /// The lobby has been sealed by the host.
    #[signal]
    fn lobby_sealed();

    // ── Called by NetworkHandler ─────────────────────────────────────────────

    /// Dispatch a parsed RTC event.  Not a GDScript-visible function — called
    /// from Rust by the parent `NetworkHandler`.
    pub fn handle_rtc_message(&mut self, msg: RtcIncoming) {
        match msg {
            RtcIncoming::PeerId { peer_id, mesh_mode } => {
                self.signals().connected().emit(peer_id, mesh_mode);
            }
            RtcIncoming::LobbyJoined { lobby_name } => {
                self.signals().lobby_joined().emit(&GString::from(lobby_name.as_str()));
            }
            RtcIncoming::PeerConnected { peer_id } => {
                self.signals().peer_connected().emit(peer_id);
            }
            RtcIncoming::PeerDisconnected { peer_id } => {
                self.signals().peer_disconnected().emit(peer_id);
            }
            RtcIncoming::Offer { from_peer_id, sdp } => {
                self.signals().offer_received().emit(from_peer_id, &GString::from(sdp.as_str()));
            }
            RtcIncoming::Answer { from_peer_id, sdp } => {
                self.signals().answer_received().emit(from_peer_id, &GString::from(sdp.as_str()));
            }
            RtcIncoming::Candidate { from_peer_id, candidate } => {
                self.signals().candidate_received().emit(from_peer_id, &GString::from(candidate.as_str()));
            }
            RtcIncoming::LobbySealed => {
                self.signals().lobby_sealed().emit();
            }
        }
    }

    // ── Outgoing helpers (client → server) ──────────────────────────────────

    /// Send a JSON string through the parent `NetworkHandler`'s WebSocket.
    fn send_to_network(&mut self, json: String) {
        if let Some(mut parent) = self.base().get_parent() {
            parent.call("send_ws_text", &[GString::from(json.as_str()).to_variant()]);
        } else {
            godot_error!("MultiplayerSessionHandler: no parent found — must be a child of NetworkHandler");
        }
    }

    /// Create a new lobby.  `mesh_mode = true` for peer-to-peer mesh,
    /// `false` to use the host as a relay.
    #[func]
    pub fn create_lobby(&mut self, mesh_mode: bool) {
        let json = serde_json::json!({
            "type": "rtc-create-lobby",
            "mesh_mode": mesh_mode,
        })
        .to_string();
        self.send_to_network(json);
    }

    /// Join an existing lobby by its lobby name.
    #[func]
    pub fn join_lobby(&mut self, lobby_name: GString) {
        let json = serde_json::json!({
            "type": "rtc-join-lobby",
            "lobby_name": lobby_name.to_string(),
        })
        .to_string();
        self.send_to_network(json);
    }

    /// Send a WebRTC offer SDP to `dest_peer_id`.
    #[func]
    pub fn send_offer(&mut self, dest_peer_id: i32, sdp: GString) {
        let json = serde_json::json!({
            "type": "rtc-offer",
            "dest_peer_id": dest_peer_id,
            "sdp": sdp.to_string(),
        })
        .to_string();
        self.send_to_network(json);
    }

    /// Send a WebRTC answer SDP to `dest_peer_id`.
    #[func]
    pub fn send_answer(&mut self, dest_peer_id: i32, sdp: GString) {
        let json = serde_json::json!({
            "type": "rtc-answer",
            "dest_peer_id": dest_peer_id,
            "sdp": sdp.to_string(),
        })
        .to_string();
        self.send_to_network(json);
    }

    /// Send an ICE candidate to `dest_peer_id`.
    #[func]
    pub fn send_candidate(&mut self, dest_peer_id: i32, candidate: GString) {
        let json = serde_json::json!({
            "type": "rtc-candidate",
            "dest_peer_id": dest_peer_id,
            "candidate": candidate.to_string(),
        })
        .to_string();
        self.send_to_network(json);
    }

    /// Seal the lobby (host only).  After sealing no new peers can join.
    #[func]
    pub fn seal_lobby(&mut self) {
        let json = serde_json::json!({ "type": "rtc-seal-lobby" }).to_string();
        self.send_to_network(json);
    }
}

#[godot_api]
impl INode for MultiplayerSessionHandler {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}
