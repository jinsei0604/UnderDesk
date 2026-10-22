# Boss room titles

The approved astronaut, Gentleman and mechanical samurai (Musha) rooms are registered. `rbm_title_room_catalog.gd`
chooses once per application process with a private RNG, then retains that room
when the launcher is recreated or the player returns home. Add each subsequently
approved `PackedScene` to `ROOMS` to include it in the next launch's random draw.
Do not register unapproved placeholders or battle sprites as finished rooms.

Room contract: a `Node2D` drawn on the 640×360 pixel grid, an `advance(seconds)`
method, and optionally `sync_clock()` for real local time. The shared shell owns
the unchanged official wordmark, START, aspect-preserving layout, full-window click/touch and keyboard activation, one START click cue,
and 0.18-second handoff to the existing home screen. Room code does not select
other rooms, manage navigation or change audio buses.

The astronaut uses the approved silent v2 preview: one intact seated sprite with
connected mesh deformation, monitor cursor synchronized to mouse use, and the
enlarged hand aura. Native room and seated textures are the approved preview
assets, not replacements for the battle sprites. Existing astronaut battle
frames and VFX drawing primitives remain dependencies. No preview recorder,
filesystem capture path, OS mouse hiding or global audio mute is shipped.

The Gentleman uses approved preview v12, including the 3.2-second fire cycle
with 96 solid pixel poses, the rigid chair/sitter surface, depth-tilted cup,
two practice shots and the existing skill shadow/head glance. Its native room
surface is 320x180. Optional `native_viewport_size()` and
`take_presentation_layer()` hooks preserve that pixel density and composite the
rigid sitter on the 1280x720 design canvas before shared UI. The shell calls
`set_presentation_active(active)` to suspend its internal viewport after START.
Room textures are packaged assets; no preview capture paths or runtime asset
preparation/writes are shipped. Ambient, gunfire and shadow animations are silent.


The Musha room uses approved preview v6. Its complete 24-cel seated character
contains the connected head, body, hands, cloth and katana; no body/weapon masks
or copied head layer are used. A 15-drawings/second outward-and-return wipe takes
3.33 seconds, starts at 4, 14, 24 and 34 seconds, and repeats every 40 seconds.
The character surface is 640x360 with nearest filtering; a nested 320x180 room
surface preserves the approved room, bamboo view, incense and lamp pixels.
The existing Musha battle background is sampled through an AtlasTexture, without
reading/decompressing its image into a new texture at startup. The existing
set_presentation_active hook stops the nested viewport after START or while
hidden. No common shell changes or changes to the Gentleman's startup
optimization are required. The room is silent and uses the shared START cue.
