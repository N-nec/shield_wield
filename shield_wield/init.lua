local SW = rawget(_G, "shield_wield")
if type(SW) ~= "table" then
    SW = {}
    rawset(_G, "shield_wield", SW)
end

SW.entities = SW.entities or {}
SW._registered_shields = SW._registered_shields or {}
SW.EXTERNAL_SHIELD_UI_ENABLED = SW.EXTERNAL_SHIELD_UI_ENABLED or false

local storage = minetest.get_mod_storage()

local function clamp(v, min_v, max_v)
    if v < min_v then
        return min_v
    end
    if v > max_v then
        return max_v
    end
    return v
end

local function copy_vec(v, fallback)
    fallback = type(fallback) == "table" and fallback or {x = 0, y = 0, z = 0}
    v = type(v) == "table" and v or {}
    return {
        x = tonumber(v.x) or tonumber(fallback.x) or 0,
        y = tonumber(v.y) or tonumber(fallback.y) or 0,
        z = tonumber(v.z) or tonumber(fallback.z) or 0,
    }
end

local default_visual_scale = tonumber(minetest.settings:get("shield_wield_visual_scale")) or 0.45
default_visual_scale = clamp(default_visual_scale, 0.05, 3)

local ATTACH_DEFAULTS = {
    bone = "Arm_Left",
    carry_pos = {x = 1.700, y = 4.900, z = 0.200},
    carry_rot = {x = 181.000, y = 90.000, z = 0.000},
    block_pos = {x = 1.300, y = 5.350, z = -3.100},
    block_rot = {x = 82.700, y = -5.000, z = -25.000},
    visual_size = {x = default_visual_scale, y = default_visual_scale, z = default_visual_scale},
}

local ARM_POSE_DEFAULTS = {
    bone = "Arm_Left",
 carry_pos = {x = 0.000, y = 0.000, z = 0.000},
 carry_rot = {x = 0.000, y = 0.000, z = 0.000},
 block_pos = {x = 0.000, y = 0.000, z = 0.000},
 block_rot = {x = 100.00, y = -30.00, z = 0.000},
}

local function normalize_attach_pose(src)
    src = type(src) == "table" and src or {}
    local bone = src.bone
    if type(bone) ~= "string" then
        bone = ATTACH_DEFAULTS.bone
    end

    return {
        bone = bone,
        carry_pos = copy_vec(src.carry_pos, ATTACH_DEFAULTS.carry_pos),
        carry_rot = copy_vec(src.carry_rot, ATTACH_DEFAULTS.carry_rot),
        block_pos = copy_vec(src.block_pos, ATTACH_DEFAULTS.block_pos),
        block_rot = copy_vec(src.block_rot, ATTACH_DEFAULTS.block_rot),
        visual_size = copy_vec(src.visual_size, ATTACH_DEFAULTS.visual_size),
    }
end

local function persist_attach_pose()
    storage:set_string("attach_pose", minetest.serialize(SW.attach))
end

local function normalize_arm_pose(src)
    src = type(src) == "table" and src or {}
    local bone = src.bone
    if type(bone) ~= "string" then
        bone = ARM_POSE_DEFAULTS.bone
    end

    return {
        bone = bone,
        carry_pos = copy_vec(src.carry_pos, ARM_POSE_DEFAULTS.carry_pos),
        carry_rot = copy_vec(src.carry_rot, ARM_POSE_DEFAULTS.carry_rot),
        block_pos = copy_vec(src.block_pos, ARM_POSE_DEFAULTS.block_pos),
        block_rot = copy_vec(src.block_rot, ARM_POSE_DEFAULTS.block_rot),
    }
end

local function persist_arm_pose()
    storage:set_string("arm_pose", minetest.serialize(SW.arm_pose))
end

SW.SLOT_NAME = minetest.settings:get("shield_wield_slot_name") or "shield"
if SW.SLOT_NAME == "" then
    SW.SLOT_NAME = "shield"
end

SW.NAME_MATCH = minetest.settings:get_bool("shield_wield_name_match", true)
SW.CUSTOM_INVENTORY = minetest.settings:get_bool("shield_wield_custom_inventory", true)
SW.BLOCK_DOT = clamp(tonumber(minetest.settings:get("shield_wield_block_dot")) or 0.2, -1, 1)
SW.BLOCK_DAMAGE_REDUCTION = clamp(tonumber(minetest.settings:get("shield_wield_block_reduction")) or 0.6, 0, 1)
SW.SCALE_BY_SHIELD_QUALITY = minetest.settings:get_bool("shield_wield_scale_by_quality", true)
SW.SHIELD_TIER_STEP = clamp(tonumber(minetest.settings:get("shield_wield_tier_step")) or 0.1, 0, 0.5)
SW.UPDATE_INTERVAL = tonumber(minetest.settings:get("shield_wield_update_interval")) or 0.05
SW.UPDATE_INTERVAL = clamp(SW.UPDATE_INTERVAL, 0.01, 1)

SW.attach = normalize_attach_pose(minetest.deserialize(storage:get_string("attach_pose")))
SW.arm_pose = normalize_arm_pose(minetest.deserialize(storage:get_string("arm_pose")))
SW._arm_pose_active = SW._arm_pose_active or {}
SW._shield_reduction_override = SW._shield_reduction_override or {}
SW._shield_tier_override = SW._shield_tier_override or {}

local function item_is_shield(itemname)
    if type(itemname) ~= "string" or itemname == "" then
        return false
    end

    if SW._registered_shields[itemname] then
        return true
    end

    local def = minetest.registered_items[itemname]
    if not def then
        return false
    end

    local groups = type(def.groups) == "table" and def.groups or {}
    if (tonumber(groups.shield) or 0) > 0
        or (tonumber(groups.armor_shield) or 0) > 0
        or (tonumber(groups.shield_wield) or 0) > 0 then
        return true
    end

    if SW.NAME_MATCH and itemname:lower():find("shield", 1, true) then
        return true
    end

    return false
end

function SW.register_shield_item(itemname, opts)
    if type(itemname) ~= "string" or itemname == "" then
        return
    end
    SW._registered_shields[itemname] = true

    if type(opts) ~= "table" then
        return
    end

    local reduction = tonumber(opts.block_reduction or opts.reduction)
    if reduction then
        SW._shield_reduction_override[itemname] = clamp(reduction, 0, 0.95)
    end

    local tier = tonumber(opts.shield_tier or opts.tier)
    if tier then
        SW._shield_tier_override[itemname] = math.max(1, math.floor(tier + 0.5))
    end
end

function SW.item_is_shield(itemname)
    return item_is_shield(itemname)
end

local function infer_shield_tier(itemname)
    local override_tier = SW._shield_tier_override[itemname]
    if override_tier then
        return override_tier
    end

    local def = minetest.registered_items[itemname]
    local groups = (def and type(def.groups) == "table") and def.groups or {}

    local group_tier = tonumber(groups.shield_tier)
        or tonumber(groups.armor_level)
        or tonumber(groups.level)
    if group_tier and group_tier > 0 then
        return math.max(1, math.floor(group_tier + 0.5))
    end

    local lname = itemname:lower()
    if lname:find("wood", 1, true) or lname:find("cactus", 1, true) then
        return 1
    end
    if lname:find("diamond", 1, true)
        or lname:find("mese", 1, true)
        or lname:find("obsidian", 1, true)
        or lname:find("mithril", 1, true) then
        return 3
    end

    return 2
end

function SW.get_block_reduction_for_item(itemname)
    local base = SW.BLOCK_DAMAGE_REDUCTION
    if type(itemname) ~= "string" or itemname == "" then
        return base
    end

    local override = SW._shield_reduction_override[itemname]
    if override then
        return override
    end

    if not SW.SCALE_BY_SHIELD_QUALITY then
        return base
    end

    local tier = infer_shield_tier(itemname)
    local scaled = base + ((tier - 2) * SW.SHIELD_TIER_STEP)
    return clamp(scaled, 0.15, 0.95)
end

local function build_inventory_formspec(player)
    local inv = player and player:get_inventory() or nil
    local has_craft = inv and inv:get_size("craft") >= 4
    local has_preview = inv and inv:get_size("craftpreview") >= 1

    local fs = {
        "formspec_version[6]",
        "size[11.6,10.4]",
        "label[0.45,0.35;Loadout]",
        "label[0.45,2.05;Shield]",
        "list[current_player;" .. SW.SLOT_NAME .. ";0.45,0.75;1,1;]",
        "label[0.45,3.0;Inventory]",
        "list[current_player;main;0.45,3.4;8,4;8]",
        "list[current_player;main;0.45,8.15;8,1;0]",
        "listring[current_player;" .. SW.SLOT_NAME .. "]",
        "listring[current_player;main]",
    }

    if has_craft then
        fs[#fs + 1] = "label[2.15,0.35;Craft]"
        fs[#fs + 1] = "list[current_player;craft;2.15,0.8;2,2;]"
        fs[#fs + 1] = "listring[current_player;craft]"
        fs[#fs + 1] = "listring[current_player;main]"
        if has_preview then
            fs[#fs + 1] = "list[current_player;craftpreview;4.7,1.3;1,1;]"
        end
    end

    return table.concat(fs)
end

local function sanitize_shield_slot(player)
    if not player or not player:is_player() then
        return
    end

    local inv = player:get_inventory()
    if not inv or inv:get_size(SW.SLOT_NAME) <= 0 then
        return
    end

    local stack = inv:get_stack(SW.SLOT_NAME, 1)
    if not stack or stack:is_empty() then
        return
    end

    if item_is_shield(stack:get_name()) then
        return
    end

    local leftover = inv:add_item("main", stack)
    inv:set_stack(SW.SLOT_NAME, 1, leftover)
end

function SW.apply_inventory_layout(player)
    if not player or not player:is_player() then
        return
    end

    local inv = player:get_inventory()
    if not inv then
        return
    end

    if inv:get_size("main") == 0 then
        inv:set_size("main", 32)
    end
    if inv:get_size("craft") == 0 then
        inv:set_size("craft", 4)
    end
    if inv:get_size(SW.SLOT_NAME) == 0 then
        inv:set_size(SW.SLOT_NAME, 1)
    end

    sanitize_shield_slot(player)

    if SW.CUSTOM_INVENTORY and not SW.EXTERNAL_SHIELD_UI_ENABLED then
        player:set_inventory_formspec(build_inventory_formspec(player))
    end
end

local function get_shield_item_from_list(inv, list_name)
    if inv:get_size(list_name) <= 0 then
        return nil
    end

    for i = 1, inv:get_size(list_name) do
        local stack = inv:get_stack(list_name, i)
        if stack and not stack:is_empty() then
            local itemname = stack:get_name()
            if item_is_shield(itemname) then
                return itemname
            end
        end
    end

    return nil
end

function SW.get_shield_itemname(player)
    if not player or not player:is_player() then
        return nil
    end

    SW.apply_inventory_layout(player)

    local inv = player:get_inventory()
    if not inv then
        return nil
    end

    local itemname = get_shield_item_from_list(inv, SW.SLOT_NAME)
    if itemname then
        return itemname
    end

    if SW.SLOT_NAME ~= "shield" then
        itemname = get_shield_item_from_list(inv, "shield")
        if itemname then
            return itemname
        end
    end

    itemname = get_shield_item_from_list(inv, "armor")
    if itemname then
        return itemname
    end

    return nil
end

function SW.player_has_shield(player)
    return SW.get_shield_itemname(player) ~= nil
end

function SW.is_shield_raised(player)
    if not SW.player_has_shield(player) then
        return false
    end

    local controls = player:get_player_control() or {}
    return controls.sneak and true or false
end

local function clear_arm_pose(player)
    if not player or not player:is_player() then
        return
    end

    local name = player:get_player_name()
    local active_bone = SW._arm_pose_active[name]
    if type(active_bone) == "string" and active_bone ~= "" then
        player:set_bone_override(active_bone, {
            rotation = {vec = {x = 0, y = 0, z = 0}, absolute = false, interpolation = 0.1},
            position = {vec = {x = 0, y = 0, z = 0}, absolute = false, interpolation = 0.1},
        })
    end
    SW._arm_pose_active[name] = nil
end

local function apply_arm_pose(player, raised)
    if not player or not player:is_player() then
        return
    end

    local bone = SW.arm_pose and SW.arm_pose.bone or ""
    if bone == "root" or bone == "(root)" then
        bone = ""
    end
    if bone == "" then
        clear_arm_pose(player)
        return
    end

    local name = player:get_player_name()
    local prev_bone = SW._arm_pose_active[name]
    if type(prev_bone) == "string" and prev_bone ~= "" and prev_bone ~= bone then
        player:set_bone_override(prev_bone, {
            rotation = {vec = {x = 0, y = 0, z = 0}, absolute = false, interpolation = 0.1},
            position = {vec = {x = 0, y = 0, z = 0}, absolute = false, interpolation = 0.1},
        })
    end

    local pos = raised and SW.arm_pose.block_pos or SW.arm_pose.carry_pos
    local rot = raised and SW.arm_pose.block_rot or SW.arm_pose.carry_rot
    rot = copy_vec(rot, {x = 0, y = 0, z = 0})

    player:set_bone_override(bone, {
        position = {
            vec = copy_vec(pos, {x = 0, y = 0, z = 0}),
            interpolation = 0.1,
            absolute = false,
        },
        rotation = {
            vec = {
                x = math.rad(tonumber(rot.x) or 0),
                y = math.rad(tonumber(rot.y) or 0),
                z = math.rad(tonumber(rot.z) or 0),
            },
            interpolation = 0.1,
            absolute = false,
        },
    })

    SW._arm_pose_active[name] = bone
end

local ENTITY_NAME = "shield_wield:shield_entity"

minetest.register_entity(ENTITY_NAME, {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        pointable = false,
        visual = "wielditem",
        wield_item = "air",
        visual_size = copy_vec(SW.attach.visual_size, ATTACH_DEFAULTS.visual_size),
        use_texture_alpha = true,
        backface_culling = false,
        static_save = false,
    },
    _player = nil,
    _itemname = nil,
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
    end,
    on_step = function(self)
        if not self._player or not self._player:is_player() then
            self.object:remove()
            return
        end

        local name = self._player:get_player_name()
        if SW.entities[name] ~= self.object then
            self.object:remove()
            return
        end

        local current_item = SW.get_shield_itemname(self._player)
        if not current_item then
            SW.entities[name] = nil
            self.object:remove()
            return
        end

        local shown_item = (self.object:get_properties() or {}).wield_item
        if current_item ~= self._itemname or shown_item ~= current_item then
            self._itemname = current_item
            self.object:set_properties({wield_item = current_item})
        end

        local raised = SW.is_shield_raised(self._player)
        local pos = raised and SW.attach.block_pos or SW.attach.carry_pos
        local rot = raised and SW.attach.block_rot or SW.attach.carry_rot

        self.object:set_properties({visual_size = copy_vec(SW.attach.visual_size, ATTACH_DEFAULTS.visual_size)})

        local bone = SW.attach.bone
        if bone == "root" or bone == "(root)" then
            bone = ""
        end
        self.object:set_attach(self._player, bone or "", pos, rot, true)
    end,
})

function SW.hide_shield(player)
    if not player or not player:is_player() then
        return
    end

    local name = player:get_player_name()
    local obj = SW.entities[name]
    if obj and obj:get_luaentity() then
        obj:remove()
    end
    SW.entities[name] = nil
    clear_arm_pose(player)
end

function SW.show_shield(player, itemname)
    if not player or not player:is_player() then
        return
    end

    local name = player:get_player_name()
    local obj = SW.entities[name]
    if obj and obj:get_luaentity() then
        local ent = obj:get_luaentity()
        if ent then
            ent._player = player
            ent._itemname = itemname
        end
        obj:set_properties({wield_item = itemname})
        return
    end

    obj = minetest.add_entity(player:get_pos(), ENTITY_NAME)
    if not obj then
        return
    end

    local ent = obj:get_luaentity()
    if ent then
        ent._player = player
        ent._itemname = itemname
    end
    obj:set_properties({wield_item = itemname})
    SW.entities[name] = obj
end

local update_player_shield

local function refresh_all_players()
    for _, player in ipairs(minetest.get_connected_players()) do
        update_player_shield(player)
    end
end

update_player_shield = function(player)
    local itemname = SW.get_shield_itemname(player)
    if itemname then
        SW.show_shield(player, itemname)
        apply_arm_pose(player, SW.is_shield_raised(player))
    else
        SW.hide_shield(player)
    end
end

local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < SW.UPDATE_INTERVAL then
        return
    end
    timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        update_player_shield(player)
    end
end)

minetest.register_on_joinplayer(function(player)
    SW.apply_inventory_layout(player)
    minetest.after(0.25, function()
        if player and player:is_player() then
            SW.apply_inventory_layout(player)
            update_player_shield(player)
        end
    end)
end)

minetest.register_on_leaveplayer(function(player)
    SW.hide_shield(player)
end)

minetest.register_on_respawnplayer(function(player)
    minetest.after(0, function()
        if player and player:is_player() then
            update_player_shield(player)
        end
    end)
end)

local function allow_inventory_put(list_name, stack)
    if list_name ~= SW.SLOT_NAME then
        return stack and stack:get_count() or 0
    end

    if stack and not stack:is_empty() and item_is_shield(stack:get_name()) then
        return stack:get_count()
    end

    return 0
end

local function allow_inventory_move(player, from_list, from_index, to_list, count)
    if to_list ~= SW.SLOT_NAME then
        return count
    end

    local inv = player and player:get_inventory() or nil
    if not inv then
        return 0
    end

    local stack = inv:get_stack(from_list, from_index)
    if stack and not stack:is_empty() and item_is_shield(stack:get_name()) then
        return count
    end

    return 0
end

if type(minetest.register_allow_player_inventory_put) == "function"
    and type(minetest.register_allow_player_inventory_move) == "function" then
    minetest.register_allow_player_inventory_put(function(_, list_name, _, stack)
        return allow_inventory_put(list_name, stack)
    end)

    minetest.register_allow_player_inventory_move(function(player, from_list, from_index, to_list, _, count)
        return allow_inventory_move(player, from_list, from_index, to_list, count)
    end)
elseif type(minetest.register_allow_player_inventory_action) == "function" then
    minetest.register_allow_player_inventory_action(function(player, action, inventory, info)
        info = type(info) == "table" and info or {}

        if action == "put" then
            local stack = info.stack
            if not stack and inventory and info.listname and info.index then
                stack = inventory:get_stack(info.listname, info.index)
            end
            return allow_inventory_put(info.listname, stack)
        end

        if action == "move" then
            local count = tonumber(info.count) or 0
            return allow_inventory_move(player, info.from_list, info.from_index, info.to_list, count)
        end

        if action == "take" then
            return tonumber(info.count) or 0
        end

        return tonumber(info.count) or 0
    end)
else
    minetest.log("warning", "[shield_wield] No supported player inventory allow-callback API found; shield slot will be sanitized after actions.")
end

if type(minetest.register_on_player_inventory_action) == "function" then
    minetest.register_on_player_inventory_action(function(player)
        sanitize_shield_slot(player)
        update_player_shield(player)
    end)
end

local function is_attack_from_front(player, attacker)
    if not (attacker and attacker.get_pos) then
        return false
    end

    local attacker_pos = attacker:get_pos()
    local player_pos = player:get_pos()
    if not attacker_pos or not player_pos then
        return false
    end

    local incoming_dir = vector.direction(attacker_pos, player_pos)
    if vector.length(incoming_dir) == 0 then
        return true
    end

    incoming_dir = vector.normalize(incoming_dir)
    local look_dir = vector.normalize(player:get_look_dir() or {x = 0, y = 0, z = 1})
    return vector.dot(look_dir, incoming_dir) >= SW.BLOCK_DOT
end

minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if hp_change >= 0 then
        return hp_change
    end
    if not SW.is_shield_raised(player) then
        return hp_change
    end

    if not reason or reason.type ~= "punch" then
        return hp_change
    end
    if not is_attack_from_front(player, reason.object) then
        return hp_change
    end

    local shield_item = SW.get_shield_itemname(player)
    local block_reduction = SW.get_block_reduction_for_item(shield_item)
    local damage = math.abs(hp_change)
    local kept_damage = math.floor((damage * (1 - block_reduction)) + 0.5)
    if kept_damage < 1 and damage > 0 then
        kept_damage = 1
    end

    return -kept_damage
end, true)

local function register_unified_inventory_shield_page()
    local ui = rawget(_G, "unified_inventory")
    if type(ui) ~= "table"
        or type(ui.pages) ~= "table"
        or type(ui.register_page) ~= "function"
        or type(ui.single_slot) ~= "function" then
        return false
    end

    local craft_page = ui.pages.craft
    if type(craft_page) ~= "table"
        or type(craft_page.get_formspec) ~= "function" then
        return false
    end

    if craft_page._shield_wield_wrapped or craft_page._game_gun_shield_wrapped then
        return true
    end

    local wrapped_page = {}
    for key, value in pairs(craft_page) do
        wrapped_page[key] = value
    end

    wrapped_page._shield_wield_wrapped = true
    wrapped_page.get_formspec = function(player, perplayer_formspec)
        local F = minetest.formspec_escape
        local S = minetest.get_translator("unified_inventory")
        local player_name = player:get_player_name()
        local formspec_style = perplayer_formspec
        if not formspec_style and type(ui.get_per_player_formspec) == "function" then
            formspec_style = ui.get_per_player_formspec(player_name)
        end
        formspec_style = formspec_style or ui.style_full or {}

        local formheaderx = tonumber(formspec_style.form_header_x) or 0
        local formheadery = tonumber(formspec_style.form_header_y) or 0
        local craftx = tonumber(formspec_style.craft_x) or 2.15
        local crafty = tonumber(formspec_style.craft_y) or 0.8
        local list_offset = tonumber(ui.list_img_offset) or 0
        local slot_x = craftx - 2.5
        local slot_y = crafty + 2.5

        local formspec = {
            formspec_style.standard_inv_bg or "",
            formspec_style.craft_grid or "",
            string.format("label[%f,%f;%s]", formheaderx, formheadery, F(S("Crafting"))),
            "listcolors[#00000000;#00000000]",
            "listring[current_name;craft]",
            "listring[current_player;main]",
            ui.single_slot(slot_x, slot_y),
            string.format("label[%f,%f;%s]", slot_x + 0.2, slot_y - 0.1, F("Shield:")),
            string.format("list[current_player;%s;%f,%f;1,1;]", SW.SLOT_NAME, slot_x + list_offset, slot_y + list_offset),
            string.format("listring[current_player;%s]", SW.SLOT_NAME),
            "listring[current_player;main]",
        }

        if (ui.trash_enabled or ui.is_creative(player_name) or minetest.get_player_privs(player_name).give)
            and type(ui.make_trash_slot) == "function" then
            formspec[#formspec + 1] = string.format("label[%f,%f;%s]", craftx + 6.45, crafty + 2.4, F(S("Trash:")))
            formspec[#formspec + 1] = ui.make_trash_slot(craftx + 6.25, crafty + 2.5)
        end

        return {formspec = table.concat(formspec)}
    end

    ui.register_page("craft", wrapped_page)
    return true
end

local function register_i3_shield_slot()
    local i3 = rawget(_G, "i3")
    if type(i3) ~= "table"
        or type(i3.get_tabs) ~= "function"
        or type(i3.override_tab) ~= "function" then
        return false
    end

    local inventory_def
    for _, def in ipairs(i3.get_tabs()) do
        if type(def) == "table" and def.name == "inventory" then
            inventory_def = def
            break
        end
    end

    if type(inventory_def) ~= "table" or type(inventory_def.formspec) ~= "function" then
        return false
    end

    if inventory_def._shield_wield_wrapped or inventory_def._game_gun_shield_wrapped then
        return true
    end

    local original_formspec = inventory_def.formspec
    local wrapped_def = {}
    for key, value in pairs(inventory_def) do
        wrapped_def[key] = value
    end

    wrapped_def._shield_wield_wrapped = true
    wrapped_def.formspec = function(player, data, fs)
        original_formspec(player, data, fs)

        local shield_x = (data and data.legacy_inventory) and 2.55 or 2.75
        local shield_y = (data and data.legacy_inventory) and 5.35 or 5.55

        fs(string.format("label[%f,%f;Shield]", shield_x, shield_y - 0.45))
        fs(string.format("list[current_player;%s;%f,%f;1,1;]", SW.SLOT_NAME, shield_x, shield_y))
        fs(string.format("listring[current_player;%s]", SW.SLOT_NAME))
        fs("listring[current_player;main]")
    end

    i3.override_tab("inventory", wrapped_def)
    return true
end

minetest.register_on_mods_loaded(function()
    local external_ui_enabled = false

    if register_unified_inventory_shield_page() then
        external_ui_enabled = true
    end
    if register_i3_shield_slot() then
        external_ui_enabled = true
    end
    if minetest.get_modpath("3d_armor") then
        external_ui_enabled = true
    end

    SW.EXTERNAL_SHIELD_UI_ENABLED = external_ui_enabled

    for _, player in ipairs(minetest.get_connected_players()) do
        SW.apply_inventory_layout(player)
        update_player_shield(player)
    end
end)

local function format_vec(v)
    return "{x = " .. string.format("%.3f", tonumber(v.x) or 0)
        .. ", y = " .. string.format("%.3f", tonumber(v.y) or 0)
        .. ", z = " .. string.format("%.3f", tonumber(v.z) or 0) .. "}"
end

local function get_pose_report()
    local bone = SW.attach.bone
    if bone == "" then
        bone = "(root)"
    end

    return "bone = " .. bone
        .. "\ncarry_pos = " .. format_vec(SW.attach.carry_pos)
        .. "\ncarry_rot = " .. format_vec(SW.attach.carry_rot)
        .. "\nblock_pos = " .. format_vec(SW.attach.block_pos)
        .. "\nblock_rot = " .. format_vec(SW.attach.block_rot)
        .. "\nsize = " .. format_vec(SW.attach.visual_size)
end

local function save_pose_and_refresh()
    persist_attach_pose()
    refresh_all_players()
end

local function get_arm_pose_report()
    local bone = SW.arm_pose.bone
    if bone == "" then
        bone = "(root)"
    end

    return "bone = " .. bone
        .. "\ncarry_pos = " .. format_vec(SW.arm_pose.carry_pos)
        .. "\ncarry_rot = " .. format_vec(SW.arm_pose.carry_rot)
        .. "\nblock_pos = " .. format_vec(SW.arm_pose.block_pos)
        .. "\nblock_rot = " .. format_vec(SW.arm_pose.block_rot)
end

local function save_arm_pose_and_refresh()
    persist_arm_pose()
    refresh_all_players()
end

minetest.register_chatcommand("shield_wield", {
    params = "[carry|block] <pos|rot> <x|y|z> <delta> | bone <name|root> | size <x|y|z> <delta>",
    description = "Tune shield wield position and rotation",
    privs = {server = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end

        local args = {}
        for word in tostring(param or ""):gmatch("%S+") do
            args[#args + 1] = word
        end

        local mode = "carry"
        local action = args[1]
        local base = 1

        if action == "carry" or action == "block" then
            mode = action
            action = args[2]
            base = 2
        end

        if not action or action == "get" or action == "print" then
            return true, get_pose_report()
        end

        if action == "help" then
            return true,
                "Usage:\n"
                .. "/shield_wield\n"
                .. "/shield_wield get\n"
                .. "/shield_wield bone <bone_name|root>\n"
                .. "/shield_wield carry pos <x|y|z> <delta>\n"
                .. "/shield_wield carry rot <x|y|z> <delta>\n"
                .. "/shield_wield block pos <x|y|z> <delta>\n"
                .. "/shield_wield block rot <x|y|z> <delta>\n"
                .. "/shield_wield size <x|y|z> <delta>"
        end

        if action == "bone" then
            local bone = args[base + 1] or ""
            if bone == "root" or bone == "(root)" or bone == "none" or bone == "nil" or bone == "\"\"" then
                bone = ""
            end
            SW.attach.bone = bone
            save_pose_and_refresh()
            return true, get_pose_report()
        end

        if action == "size" then
            local axis = args[base + 1]
            local delta = tonumber(args[base + 2])
            if axis ~= "x" and axis ~= "y" and axis ~= "z" then
                return false, "Axis must be x, y, or z."
            end
            if not delta then
                return false, "Delta must be a number."
            end

            SW.attach.visual_size[axis] = math.max(0.05, (tonumber(SW.attach.visual_size[axis]) or 0) + delta)
            save_pose_and_refresh()
            return true, get_pose_report()
        end

        if action ~= "pos" and action ~= "rot" then
            return false, "Expected 'pos', 'rot', 'size', or 'bone'. Try /shield_wield help"
        end

        local axis = args[base + 1]
        local delta = tonumber(args[base + 2])
        if axis ~= "x" and axis ~= "y" and axis ~= "z" then
            return false, "Axis must be x, y, or z."
        end
        if not delta then
            return false, "Delta must be a number."
        end

        local key = mode .. "_" .. action
        if type(SW.attach[key]) ~= "table" then
            SW.attach[key] = {x = 0, y = 0, z = 0}
        end

        SW.attach[key][axis] = (tonumber(SW.attach[key][axis]) or 0) + delta
        save_pose_and_refresh()

        return true, get_pose_report()
    end,
})

minetest.register_chatcommand("sw_arm", {
    params = "[carry|block] <pos|rot> <x|y|z> <delta> | bone <name|root>",
    description = "Tune shield arm carry/block pose",
    privs = {server = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end

        local args = {}
        for word in tostring(param or ""):gmatch("%S+") do
            args[#args + 1] = word
        end

        local mode = "carry"
        local action = args[1]
        local base = 1
        if action == "carry" or action == "block" then
            mode = action
            action = args[2]
            base = 2
        end

        if not action or action == "get" or action == "print" then
            return true, get_arm_pose_report()
        end

        if action == "help" then
            return true,
                "Usage:\n"
                .. "/sw_arm\n"
                .. "/sw_arm get\n"
                .. "/sw_arm bone <bone_name|root>\n"
                .. "/sw_arm carry pos <x|y|z> <delta>\n"
                .. "/sw_arm carry rot <x|y|z> <delta>\n"
                .. "/sw_arm block pos <x|y|z> <delta>\n"
                .. "/sw_arm block rot <x|y|z> <delta>"
        end

        if action == "bone" then
            local bone = args[base + 1] or ""
            if bone == "root" or bone == "(root)" or bone == "none" or bone == "nil" or bone == "\"\"" then
                bone = ""
            end
            SW.arm_pose.bone = bone
            save_arm_pose_and_refresh()
            return true, get_arm_pose_report()
        end

        if action ~= "pos" and action ~= "rot" then
            return false, "Expected 'pos', 'rot', or 'bone'. Try /sw_arm help"
        end

        local axis = args[base + 1]
        local delta = tonumber(args[base + 2])
        if axis ~= "x" and axis ~= "y" and axis ~= "z" then
            return false, "Axis must be x, y, or z."
        end
        if not delta then
            return false, "Delta must be a number."
        end

        local key = mode .. "_" .. action
        if type(SW.arm_pose[key]) ~= "table" then
            SW.arm_pose[key] = {x = 0, y = 0, z = 0}
        end
        SW.arm_pose[key][axis] = (tonumber(SW.arm_pose[key][axis]) or 0) + delta

        save_arm_pose_and_refresh()
        return true, get_arm_pose_report()
    end,
})

local function open_shield_slot_formspec(player)
    local formspec = table.concat({
        "formspec_version[6]",
        "size[8.8,8.4]",
        "label[0.4,0.4;Shield Slot]",
        "list[current_player;" .. SW.SLOT_NAME .. ";0.4,0.9;1,1;]",
        "label[0.4,2.0;Inventory]",
        "list[current_player;main;0.4,2.4;8,4;8]",
        "list[current_player;main;0.4,7.15;8,1;0]",
        "listring[current_player;" .. SW.SLOT_NAME .. "]",
        "listring[current_player;main]",
    })

    minetest.show_formspec(player:get_player_name(), "shield_wield:slot", formspec)
end

minetest.register_chatcommand("shield_slot", {
    params = "",
    description = "Open a simple shield slot inventory window",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end

        SW.apply_inventory_layout(player)
        open_shield_slot_formspec(player)
        return true, "Opened shield slot window."
    end,
})

minetest.register_chatcommand("shield_equip", {
    params = "",
    description = "Move your wielded shield into the shield slot",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end

        SW.apply_inventory_layout(player)
        local wielded = player:get_wielded_item()
        if not wielded or wielded:is_empty() then
            return false, "Wield a shield item first."
        end

        local itemname = wielded:get_name()
        if not item_is_shield(itemname) then
            return false, "Wielded item is not detected as a shield."
        end

        local inv = player:get_inventory()
        if not inv then
            return false, "Inventory not available."
        end

        local slot_stack = inv:get_stack(SW.SLOT_NAME, 1)
        if slot_stack and not slot_stack:is_empty() then
            local leftover = inv:add_item("main", slot_stack)
            if leftover and not leftover:is_empty() then
                return false, "Shield slot is occupied and main inventory is full."
            end
        end

        inv:set_stack(SW.SLOT_NAME, 1, wielded)
        player:set_wielded_item(ItemStack())
        update_player_shield(player)

        return true, "Equipped shield to shield slot."
    end,
})
