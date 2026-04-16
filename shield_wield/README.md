# shield_wield

Standalone offhand shield visuals and blocking for Luanti (Minetest).

## What this mod does

- Adds a dedicated shield inventory slot (`shield` by default)
- Renders equipped shield items on the player left arm using `wielditem` visuals
- Keeps shield visible even while holding non-gun items
- Uses sneak (`Shift`) as raise/block input
- Reduces frontal punch damage while shield is raised
- Optionally scales block reduction by inferred shield quality/tier (stronger shields can block more)
- Includes live tuning commands for shield position and rotation
- Integrates with common inventory mods:
  - default inventory formspec
  - Unified Inventory craft page slot injection
  - i3 inventory tab slot injection
  - 3d_armor compatibility by reading shield items from `shield` / `armor` inventory lists

## Shield item detection

An item is treated as a shield if any of these are true:

- It was registered through `shield_wield.register_shield_item(itemname)`
- It has one of these groups: `shield`, `armor_shield`, `shield_wield`
- `shield_wield_name_match = true` and itemname contains `shield`

## Commands

Player commands:

- `/shield_slot` opens a small shield-slot inventory window (fallback for unsupported inventory UIs)
- `/shield_equip` moves the currently wielded shield item into the shield slot

Admin/server commands:

- `/shield_wield` prints current pose values
- `/shield_wield bone <bone_name|root>` sets attachment bone
- `/shield_wield carry pos <x|y|z> <delta>` nudges carry position
- `/shield_wield carry rot <x|y|z> <delta>` nudges carry rotation
- `/shield_wield block pos <x|y|z> <delta>` nudges block position
- `/shield_wield block rot <x|y|z> <delta>` nudges block rotation
- `/shield_wield size <x|y|z> <delta>` nudges visual scale
- `/sw_arm` prints current left-arm carry/block pose values
- `/sw_arm bone <bone_name|root>` sets arm pose bone
- `/sw_arm carry pos|rot <x|y|z> <delta>` nudges arm carry pose
- `/sw_arm block pos|rot <x|y|z> <delta>` nudges arm block pose

Pose values are saved in mod storage and persist across restarts.

## Settings

See `settingtypes.txt`:

- `shield_wield_custom_inventory`
- `shield_wield_slot_name`
- `shield_wield_name_match`
- `shield_wield_block_reduction`
- `shield_wield_scale_by_quality`
- `shield_wield_tier_step`
- `shield_wield_block_dot`
- `shield_wield_visual_scale`
- `shield_wield_update_interval`

## Install

1. Place this folder as its own mod directory named `shield_wield` inside your Luanti `mods` path.
2. Enable the mod for your world.
3. Join world and put a shield item in the shield slot.
