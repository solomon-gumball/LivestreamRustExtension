<svg src="./kart_movement_networking_plan_v2.svg">

Phase 1 — Connect. Do a ping/pong handshake to measure RTT. Use that to set the client's starting tick so it runs ahead of the server's simulate tick by buffer_depth + one_way_latency + a small margin. Repeat this every ~8 seconds during play and nudge the tick ±1 at a time to correct drift — never hard-set it mid-game.

Phase 2 — Per frame. The client samples input, saves it to a ring buffer entry alongside the resulting predicted state (position, velocity, rotation after that tick), applies the input locally for instant feel, and sends the packet unreliably. The server stores incoming inputs in a per-client queue indexed by tick, simulates its current tick each frame using whatever inputs have arrived — falling back to last known input for dropped packets — and broadcasts a state snapshot at ~20Hz.

Phase 3 — Reconciliation. When a snapshot arrives, discard it if it's older than the last one processed. Otherwise look up your predicted state at that tick in the ring buffer and compare it to the authoritative state. If the error is below your threshold (~5px), skip the correction entirely. If it exceeds the threshold, re-simulate forward tick-by-tick from the snapshot's authoritative state to current_tick using your saved inputs from the buffer. Hard-set your physics state to the re-simulated result immediately — no lerp on the physics state itself. For remote karts, buffer 2–3 snapshots and interpolate between them rather than snapping.

Phase 4 — Visual smoothing. Keep your kart as two separate things: a physics_state that holds the true gameplay position and is always corrected instantly, and a visual_node that the player actually sees. Every render frame, lerp the visual node toward the physics state using lerp(visual, physics, 20.0 * delta). The framerate-independent weight means corrections never produce a visible pop — the visual just smoothly slides into place while gameplay logic runs on the correct authoritative state immediately.
Key requirement. simulate_one_frame() must be a pure function — deterministic, no side effects on your actual scene nodes. It's called both during normal per-frame prediction and during reconciliation re-simulation, so it must produce identical results for identical inputs both times.

SIMULATION TIMING ->

INPUT_BUFFER_DEPTH
This is how many ticks the server waits before simulating a given tick. If the server is on tick 100, it simulates tick 100 - INPUT_BUFFER_DEPTH.
Its purpose is to absorb consistent one-way latency. If a client has a 100ms ping (50ms one-way), their input for tick 100 takes ~3 ticks to arrive at 60Hz. So the server needs to wait at least 3 ticks before simulating tick 100, otherwise that client's input will never arrive in time — the server will always be falling back to last known input, which means the server and client are constantly diverging.
You size it based on your worst acceptable ping. The rule is:
INPUT_BUFFER_DEPTH >= worst_expected_one_way_latency_in_ticks
At 60Hz, one tick is ~16.6ms, so:
Worst ping you want to supportOne-wayMinimum buffer depth100ms50ms3 ticks200ms100ms6 ticks300ms150ms9 ticks
For a casual local/regional game you might set it to 6. For a game supporting players across continents, closer to 10–12. Setting it too low means high-ping players constantly miss their simulation window and get corrected every snapshot. Setting it too high adds unnecessary input delay for everyone — even a 20ms ping player will feel INPUT_BUFFER_DEPTH ticks of lag on their inputs.

MARGIN_TICKS
This is extra headroom added on top of the buffer depth when the client sets its tick offset on connect. Where INPUT_BUFFER_DEPTH handles consistent latency, MARGIN_TICKS handles jitter — the variance in how long packets take to arrive.
Even on a 50ms average ping connection, individual packets might take 30ms or 80ms. Without margin, a packet that arrives slightly late still misses its simulation window. MARGIN_TICKS ensures that even a jittery packet has time to arrive.
You size it based on your expected jitter, not base latency:
MARGIN_TICKS >= worst_expected_jitter_in_ticks
In practice 2–3 ticks is enough for most connections. Residential internet jitter is usually under 30ms, which at 60Hz is under 2 ticks.

How They Work Together
client_tick = server_simulate_tick + INPUT_BUFFER_DEPTH + MARGIN_TICKS + one_way_ticks
Think of it as three separate guarantees stacked on top of each other:

one_way_ticks — accounts for the time the packet spends in transit
INPUT_BUFFER_DEPTH — guarantees the server waits long enough for it to arrive
MARGIN_TICKS — guarantees jittery packets still arrive within that window