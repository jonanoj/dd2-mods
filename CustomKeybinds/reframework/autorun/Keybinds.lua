--[[
Custom Keybinds by jondnoj
- https://www.nexusmods.com/dragonsdogma2/mods/297/
- https://github.com/jonanoj/dd2-mods/tree/main/CustomKeybinds
 
Thanks to alphaZomega for the base code for keybind_button
]] --
local function generate_enum(typename)
    local t = sdk.find_type_definition(typename)
    if not t then
        return {}
    end

    local fields = t:get_fields()
    local enum = {}
    local ids = {}

    for i, field in ipairs(fields) do
        if field:is_static() then
            local name = field:get_name()
            local raw_value = field:get_data(nil)

            enum[name] = raw_value
            ids[raw_value] = name
        end
    end

    return enum, ids
end

local function sdk_iterator(sdk_enumerator)
    local enumerator = sdk_enumerator:call("GetEnumerator")
    return function()
        local moved = enumerator:call("MoveNext")
        if moved then
            return enumerator:call("get_Current")
        end
    end
end

local keyboard_name_to_id, keyboard_id_to_name = generate_enum("via.hid.KeyboardKey")
local mouse_name_to_id, mouse_id_to_name = generate_enum("via.hid.MouseButton")

local recording_button_id = nil
local last_pressed_key = nil

local function _keybind_button(id, current_value, width)
    local button_size = {}
    table.insert(button_size, 120)
    table.insert(button_size, 30)

    if recording_button_id == id then
        if last_pressed_key then
            recording_button_id = nil

            -- Treat Escape as 'Reset keybind'
            if last_pressed_key == keyboard_name_to_id.Escape then
                return true, 0
            end

            return true, last_pressed_key
        end

        if imgui.button("[Press any key]", button_size) then
            recording_button_id = nil
            return false, nil
        end

        if imgui.is_item_hovered() then
            imgui.set_tooltip(
                "To bind mouse keys, Press anywhere *OUTSIDE* the REFramework UI. \nPress Escape to remove keybind.")
        else

        end
    else
        if imgui.button(keyboard_id_to_name[current_value], button_size) then
            recording_button_id = id
        end
    end

    return false, nil
end

local function keybind_button(id, current_value, width)
    imgui.push_id(id)
    local changed, value = _keybind_button(id, current_value, width)
    imgui.pop_id()
    return changed, value
end

local mouse_to_keyboard_key = {
    [mouse_name_to_id.L] = keyboard_name_to_id.LButton,
    [mouse_name_to_id.R] = keyboard_name_to_id.RButton,
    [mouse_name_to_id.C] = keyboard_name_to_id.MButton,
    [mouse_name_to_id.EX0] = keyboard_name_to_id.XButton1,
    [mouse_name_to_id.EX1] = keyboard_name_to_id.XButton2
}

local keyboard = sdk.get_native_singleton("via.hid.Keyboard")
local mouse = sdk.get_native_singleton("via.hid.Mouse")
local keyboard_type = sdk.find_type_definition("via.hid.Keyboard")
local mouse_type = sdk.find_type_definition("via.hid.Mouse")

re.on_application_entry("UpdateHID", function()
    if not recording_button_id then
        last_pressed_key = nil
        return nil
    end

    local mouse_device = sdk.call_native_func(mouse, mouse_type, "get_Device")
    if mouse_device then
        for id, keyboard_key in pairs(mouse_to_keyboard_key) do
            if mouse_device:call("isRelease", id) then
                last_pressed_key = keyboard_key
                return
            end
        end
    end

    local keyboard_device = sdk.call_native_func(keyboard, keyboard_type, "get_Device")
    if keyboard_device then
        for id, name in pairs(keyboard_id_to_name) do
            if keyboard_device:call("isDown", id) then
                last_pressed_key = id
                return
            end
        end
    end
end)

local gamepad_name_to_id, gamepad_id_to_name = generate_enum("via.hid.GamePadButton")
local supported_gamepad_buttons = {}
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RLeft)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RUp)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RRight)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RDown)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LTrigTop)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LTrigBottom)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RTrigTop)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RTrigBottom)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LStickPush)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.RStickPush)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LLeft)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LUp)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LRight)
table.insert(supported_gamepad_buttons, gamepad_name_to_id.LDown)

local managed_gamepad_buttons = sdk.create_managed_array(sdk.find_type_definition("via.hid.GamePadButton"),
    #supported_gamepad_buttons):add_ref()
for i, id in pairs(supported_gamepad_buttons) do
    managed_gamepad_buttons[i - 1] = id
end

sdk.hook(sdk.find_type_definition("app.ui060806"):get_method("Initialize"), function(args)
    local ui_object = sdk.to_managed_object(args[2])
    ui_object:set_field("BasicButtons", managed_gamepad_buttons)
    ui_object:set_field("BasicButtonNum", #supported_gamepad_buttons)
    ui_object:set_field("CrossButtons", managed_gamepad_buttons)
    ui_object:set_field("CrossButtonNum", #supported_gamepad_buttons)
end, function(retval)
    return retval
end)

local character_action_name_to_id, character_action_id_to_name = generate_enum("app.CharacterInput.Action")
local system_action_name_to_id, system_action_id_to_name = generate_enum("app.SystemInput.Action")
local get_message = sdk.find_type_definition("via.gui.message"):get_method("get")

local KeyboardToIconTagTable = nil
local overwritten_keys = {}

local question_mark_key_icon = "KEY_QUESTION"
KeyboardToIconTagTable = sdk.find_type_definition("app.KeyBindEnumExtension"):get_field("_KeyboardToIconTagTable")
    :get_data(nil)

-- Replace missing keys with '?' icon
for key in pairs(keyboard_id_to_name) do
    if not KeyboardToIconTagTable:call("ContainsKey", key) then
        overwritten_keys[key] = true
        KeyboardToIconTagTable:call("Add", key, question_mark_key_icon)
    end
end

-- Clean up overwrites
re.on_script_reset(function()
    if KeyboardToIconTagTable then

    end
    for key in pairs(overwritten_keys) do
        KeyboardToIconTagTable:call("Remove", key)
    end
end)

local UserInputManager = sdk.get_managed_singleton("app.UserInputManager")
local KeyBindController = UserInputManager:call("get_KeyBindController")
local UnbindableKeyList = KeyBindController:call("get_UnbindableKeyList")
UnbindableKeyList:call("Clear")

local BindableKeyList = KeyBindController:call("get_BindableKeyList")
for key in pairs(keyboard_id_to_name) do
    BindableKeyList:call("Add", key)
end

local UserInputManagerParameter = UserInputManager:get_field("Param")
local DefaultKeybinds = UserInputManagerParameter:get_field("DefaultKeyBindSetting"):get_field("_Settings")
    :get_elements()
local command_hashes_with_shift = {}
for i, setting_item in pairs(DefaultKeybinds) do
    if setting_item:get_field("_WithCustomShift") then
        table.insert(command_hashes_with_shift, setting_item:call("get_CommandHash"))
    end
end

-- Keep up to date reference to current keybinds (in case the set is changed)
local KeyBindTable = KeyBindController:call("getCurrentKeyBindSettingTable")
sdk.hook(sdk.find_type_definition("app.KeyBindController"):get_method("setCurrentKeyBindSettingTable"), function(args)
    KeyBindTable = KeyBindController:call("getCurrentKeyBindSettingTable")
end, function(retval)
    return retval
end)

local function patch_pad_assign(PadAssign, character_action, with_shift)
    for pad_assign in sdk_iterator(PadAssign:get_field("AssignList")) do
        if pad_assign:get_field("Action") == character_action then
            local pre_input = with_shift and character_action_name_to_id["Shift1"] or
                                  character_action_name_to_id["None"]
            pad_assign:set_field("PreInput", pre_input)
            break
        end
    end
end

local function update_keybind_state(keybind, with_shift)
    keybind:set_field("_WithCustomShift", with_shift)
    KeyBindController:call("setCurrentKeyBindSettingTable", KeyBindTable)

    local character_action = keybind:call("get_CharacterCommand")
    patch_pad_assign(UserInputManager:call("getCurrentCharacterPadAssign"), character_action, with_shift)
end

local settings_file = "Keybinds.json"
local settings = json.load_file(settings_file) or {
    ["patched_commands"] = {}
}

-- Restore settings after game load
for command_hash_str, with_shift in pairs(settings.patched_commands) do
    -- No point to patch keys "with shift" turned on, since they're loaded like that
    if not with_shift then
        local command_hash = tonumber(command_hash_str)
        local keybind = KeyBindTable:call("get_Item", command_hash)
        update_keybind_state(keybind, with_shift)
    end
end

local function get_key_name(keybind)
    local msg_id = keybind:call("get_FunctionMsgId")
    local message = get_message(nil, msg_id)

    if #message > 0 then
        return message
    end

    local character_action = keybind:call("get_CharacterCommand")
    if character_action ~= 0 then
        return character_action_id_to_name[character_action]
    end

    local system_action = keybind:call("get_SystemCommand")
    if system_action ~= 0 then
        return system_action_id_to_name[system_action]
    end

    return "(UNKNOWN ACTION)"
end

local function render_keybind(keybind, show_keys)
    imgui.text(get_key_name(keybind))

    imgui.indent()

    local with_shift = keybind:call("get_WithCustomShift")
    local command_hash = keybind:call("get_CommandHash")

    if show_keys then
        local key1Changed, key1Value = keybind_button(command_hash .. "-1", keybind:call("get_PrimaryKey"))
        if key1Changed then
            keybind:set_field("_PrimaryKey", key1Value)
            return true, with_shift
        end

        imgui.same_line()

        local key1Changed, key1Value = keybind_button(command_hash .. "-2", keybind:call("get_SecondaryKey"))
        if key1Changed then
            keybind:set_field("_SecondaryKey", key1Value)
            return true, with_shift
        end
    end

    local shift_changed, should_disable = imgui.checkbox("Disable 'Switch Weapon Skill'?", not with_shift) -- Notice the negation here, UI feels more intuitive when patching is "V"
    if shift_changed then
        local with_shift = not should_disable -- Double negative, we treat this value as "WithCustomShift" internally
        return true, with_shift
    end

    imgui.unindent()

    return false, nil
end

local function save_shift_change(keybind, command_hash, with_shift)
    update_keybind_state(keybind, with_shift)

    settings.patched_commands[command_hash] = with_shift
    json.dump_file(settings_file, settings)
end

re.on_draw_ui(function()
    if imgui.tree_node("Custom Keybinds") then

        if imgui.tree_node("Advanced Settings") then
            imgui.spacing()
            imgui.spacing()
            imgui.spacing()
            imgui.begin_rect()
            imgui.text("Use this menu to bind keys that can't be changed through the in-game UI")
            imgui.spacing()
            imgui.spacing()

            for command_hash in sdk_iterator(KeyBindTable:call("get_Keys")) do
                local keybind = KeyBindTable:call("get_Item", command_hash)
                imgui.push_id("advanced-keyboard-key-" .. command_hash)
                local changed, with_shift = render_keybind(keybind, true)
                if changed then
                    save_shift_change(keybind, command_hash, with_shift)
                end
                imgui.spacing()
                imgui.spacing()
                imgui.pop_id()
            end

            imgui.end_rect(10, true)
            imgui.spacing()
            imgui.spacing()
            imgui.spacing()
            imgui.spacing()
        end

        imgui.text("Force disable 'Ctrl+X' keys:")
        imgui.spacing()
        for i, command_hash in pairs(command_hashes_with_shift) do
            imgui.push_id("keyboard-key-" .. command_hash)
            local keybind = KeyBindTable:call("get_Item", command_hash)
            local changed, with_shift = render_keybind(keybind, false)
            if changed then
                save_shift_change(keybind, command_hash, with_shift)
            end
            imgui.spacing()
            imgui.spacing()
            imgui.pop_id()
        end
    end
end)
