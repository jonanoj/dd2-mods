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

local keyboard_name_to_id, keyboard_id_to_name = generate_enum("via.hid.KeyboardKey")
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

local function render_keybind(keybind)
    imgui.text(get_key_name(keybind))

    imgui.indent()
    local with_shift = keybind:call("get_WithCustomShift")
    local shift_changed, should_disable = imgui.checkbox("Disable 'Switch Weapon Skill'?", not with_shift) -- Notice the negation here, UI feels more intuitive when patching is "V"
    if shift_changed then
        local with_shift = not should_disable -- Double negative, we treat this value as "WithCustomShift" internally
        return true, with_shift
    end

    imgui.unindent()

    return false, nil
end

re.on_draw_ui(function()
    if imgui.tree_node("Custom Keybinds") then
        imgui.text("Force disable 'Ctrl+X' keys:")
        imgui.spacing()
        for i, command_hash in pairs(command_hashes_with_shift) do
            imgui.push_id("keyboard-key-" .. command_hash)
            local keybind = KeyBindTable:call("get_Item", command_hash)
            local changed, with_shift = render_keybind(keybind)
            if changed then
                update_keybind_state(keybind, with_shift)

                settings.patched_commands[command_hash] = with_shift
                json.dump_file(settings_file, settings)
            end
            imgui.spacing()
            imgui.spacing()
            imgui.pop_id()
        end
    end
end)
