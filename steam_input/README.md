# Steam Input

`game_actions.vdf` is the in-game action manifest (IGA) for Steam Input (standards
§8.3): two action sets, `world` and `device`, with the analog and digital actions the
client exposes. It is registered at startup by `client/steam/steam_host.gd` when the
Steam client is running.

The default Deck layout binds it around the Deck's own hardware: the right trackpad
drives the device cursor, the back buttons carry the tactical reload (L4) and the AI
overlay toggle (L5) so no face button is spent on a debug action, View raises the
device, Menu is the raid spawn. The layout is bound to the app in the Steamworks
partner site, which needs the app id CEOGG registers (standards §12 item 4); until
then the action sets resolve to nothing under the test app and Godot's input map
(`project.godot`, the same actions under `world_*`) is the fallback, with the
on-screen prompts drawn from `client/input_glyphs.gd` in Deck or Xbox names.
