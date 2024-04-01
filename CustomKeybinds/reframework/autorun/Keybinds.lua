local function try_require(path)
    local success, lib = pcall(require, path)
    if (success) then
        return lib
    end

    return nil
end

local hotkeys = try_require("Hotkeys/Hotkeys")
if hotkeys then
    hotkeys.setup_hotkeys({
        ["Key Tester"] = "Click here!"
    })
end

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

local keyboard_name_to_id, keyboard_id_to_name = generate_enum("via.hid.KeyboardKey")
local character_action_name_to_id, character_action_id_to_name = generate_enum("app.CharacterInput.Action")
local system_action_name_to_id, system_action_id_to_name = generate_enum("app.SystemInput.Action")
local get_message = sdk.find_type_definition("via.gui.message"):get_method("get")

local UserInputManager
local KeyBindController
local KeyBindTable

local function sdk_iterator(sdk_enumerator)
    local enumerator = sdk_enumerator:call("GetEnumerator")
    return function()
        local moved = enumerator:call("MoveNext")
        if moved then
            return enumerator:call("get_Current")
        end
    end
end

local function render_keybind(keybind)
    local characterAction = keybind:call("get_CharacterCommand")
    local systemAction = keybind:call("get_SystemCommand")
    local msg_id = keybind:call("get_FunctionMsgId")
    local message = get_message(nil, msg_id)

    if #message > 0 then
        imgui.text(message)
    else
        imgui.text("NO MESSAGE")
    end

    imgui.same_line()

    if characterAction ~= 0 then
        imgui.text("(Character Action - " .. character_action_id_to_name[characterAction] .. ")")
    elseif systemAction ~= 0 then
        imgui.text("(System Action - " .. system_action_id_to_name[systemAction] .. ")")
    else
        imgui.text("(UNKNOWN ACTION)")
    end

    imgui.indent()

    imgui.set_next_item_width(200)
    local key1Changed, key1Value = imgui.combo("Primary Key", keybind:call("get_PrimaryKey"), keyboard_id_to_name)
    if key1Changed then
        keybind:set_field("_PrimaryKey", key1Value)
        return true
    end

    imgui.set_next_item_width(200)
    local key2Changed, key2Value = imgui.combo("Secondary Key", keybind:call("get_SecondaryKey"), keyboard_id_to_name)
    if key2Changed then
        keybind:set_field("_SecondaryKey", key2Value)
        return true
    end

    --[[ 
        Unfortunately modifying this field doesn't do anything ingame
        It seems like the UI does register the key as if it doesn't require holding the other key, but the game still requires item
        Feel free to uncomment this code snippet and experiment with it
    ]] --
    -- local shiftChanged, shiftValue = imgui.checkbox("Require 'Switch Weapon Skill'?", keybind:call("get_WithCustomShift"))
    -- if shiftChanged then
    --     keybind:set_field("_WithCustomShift", shiftValue)
    --     return true
    -- end

    if keybind:call("get_WithCustomShift") then
        imgui.text_colored("Requires holding the 'Switch Weapon Skill' key!", 0xFFAAAAFF)
    end

    imgui.unindent()

    return false
end

re.on_application_entry("UpdateHID", function()
    if not UserInputManager then
        UserInputManager = sdk.get_managed_singleton("app.UserInputManager")
    end
    if UserInputManager and not KeyBindController then
        KeyBindController = UserInputManager:call("get_KeyBindController")
    end

    if KeyBindController then
        KeyBindTable = KeyBindController:call("getCurrentKeyBindSettingTable")
    end
end)

re.on_draw_ui(function()
    if imgui.tree_node("Custom Keybinds") then
        if hotkeys then
            imgui.text("Use this key tester to check the name of special keys (such as brackets, semicolon, etc)")
            hotkeys.hotkey_setter("Key Tester")

            imgui.spacing()
            imgui.spacing()
        end

        if KeyBindTable then
            for key in sdk_iterator(KeyBindTable:call("get_Keys")) do
                imgui.push_id("keyboard-key" .. key)
                local changed = render_keybind(KeyBindTable:call("get_Item", key))
                if changed then
                    KeyBindController:call("setCurrentKeyBindSettingTable", KeyBindTable)
                    KeyBindController:call("reflectSaveData")
                end
                imgui.pop_id()
            end
        end

        imgui.tree_pop()
    end
end)
