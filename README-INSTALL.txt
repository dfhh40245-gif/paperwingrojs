PAPER WINGS — SOURCE PATCH
==========================

This is a patch bundle for the existing Rojo project, not a replacement project.
It contains only source files reconstructed from the two source dumps uploaded
in this conversation and the modified modules. Copy the included src/ files over
the matching paths in your existing RobloxRojoTest project, then run Rojo sync.
Keep the rest of your project unchanged.

FILES TO REPLACE
----------------
src/client/Flight.luau
src/client/WorldBuilder.luau
src/client/PlaneBuilder.luau
src/client/UI.luau
src/client/Effects.luau
src/shared/GameConfig.luau
src/shared/PlayerData.luau
src/shared/Stats.luau

WHAT CHANGED
------------
1. Flight now uses WASD for horizontal movement and Q/E for altitude.
   W moves along -Z, S along +Z, A/D strafe, Q descends and E ascends.
   The aircraft starts at runway height; W does not add vertical movement.

2. Flight now has velocity-based acceleration, inertia, air drag, gravity,
   runway friction, safe ground contact, smooth 3D orientation and a camera
   that follows the aircraft's current heading. Releasing all movement input
   decays horizontal momentum and lets gravity bring the aircraft to the ground.

3. Mouse position is no longer used by the movement controller. Mouse 1 fires
   continuously while held; mouse position supplies an independent 3D aiming ray.
   Space remains an optional keyboard fire binding.

4. Side and upper electrical barriers are included in streamed environment
   chunks. Touching either boundary starts a tumble/fall crash sequence; ground
   contact ends the run through the existing death/revive lifecycle.

5. A Fire Rate upgrade was added to GameConfig, PlayerData defaults, Stats and
   the generic shop upgrade catalogue. The firing interval starts slower and
   decreases with Fire Rate upgrade levels. The server purchase handler was not
   included in the uploads, so its acceptance of this new upgrade still needs
   verification in the original GameService.luau.

6. A Settings button and key-rebinding modal were added. Movement, keyboard fire
   and boost bindings can be changed and reset. In this patch bindings are kept
   in the client for the current play session only. Persisting them between
   sessions requires wiring the settings payload into the server save handler,
   which was not included in the uploaded source.

7. PlaneBuilder adds aircraft finish details (wing markings, navigation lights,
   landing struts/wheels and panel seams). Effects adds a muzzle flash.

8. WorldBuilder now has distinct recipes for all six configured zone styles:
   town, canyon, ocean, storm, clouds and fold. Missing recipes now warn and
   error rather than silently building Paper Town scenery. Each chunk also has
   translucent side/ceiling energy barriers and visible electrical arcs.

OPTIONAL STUDIO EDIT-MODE PREVIEW
---------------------------------
The tools/StudioBakePreview.command.lua file can be run from Roblox Studio's
Command Bar after Rojo has synced. It creates six static scenery samples in
Workspace.PaperWings_EditorPreview so the zone art can be inspected in Edit
mode without starting a Play session. The samples are placed side-by-side,
outside the playable corridor. Delete Workspace.PaperWings_EditorPreview before
publishing if you do not want those preview models included in the place.

LIMITATIONS / NOT VERIFIED
--------------------------
- The upload did not contain GameService.luau, DataService.luau, init.server.luau
  or default.project.json. I therefore did not invent replacements for these
  files, and cannot verify the server-side FireRate purchase path or add durable
  account-level control settings safely.
- No Roblox Studio MCP connection or Roblox runtime was available in this task.
  The modified code has been checked by source inspection and static consistency
  checks, but has not been executed or playtested in Roblox Studio.
- The world and aircraft models remain procedurally constructed from Roblox
  parts. This patch improves their construction and zone differentiation, but
  does not import third-party Creator Store mesh packs or replace the art with
  professionally authored MeshParts.
- The current touch input remains a fire/tap input; a separate mobile movement
  joystick was not added in this desktop-focused control redesign.

Recommended first Studio checks:
- Test W/S/A/D/Q/E separately and in combinations.
- Verify the plane rests on the runway and E is required to climb.
- Aim at enemies while facing sideways and backwards.
- Hold and release Mouse 1; verify fire interval changes after a Fire Rate buy.
- Hit each side barrier and the ceiling; verify tumble, fall, death and revive.
- Visit all six zones and verify their scenery is distinct.
- Open Settings and rebind every action; try duplicate keys to check rejection.
