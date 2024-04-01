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
