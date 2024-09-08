if reframework:get_game_name() ~= "re4" then
    return
end

--                      // Default values //
local defaults = {
    parry_accept_time = 1.0,        -- (0.5) Default value for _ParryParam
    ignore_parry_time = 0.03   -- (0.333) Default value for _IgnoreParryTime
}

local field_mapping = {
    parry_accept_time = "_ParryAcceptTime",
    ignore_parry_time = "_IgnoreParryTime"
}

local character_ids = {
    "ch0a0z0_head", "ch3a8z0_head", "ch6i0z0_head", "ch6i1z0_head", "ch6i2z0_head", 
    "ch6i3z0_head", "ch3a8z0_MC_head", "ch6i5z0_head"
}

local parry_presets = {
    Default = {parry_accept_time = 1.0, ignore_parry_time = 0.1},
    Easier = {parry_accept_time = 1.25, ignore_parry_time = 0.1},
    Harder = {parry_accept_time = 0.75, ignore_parry_time = 0.15},
    Professional = {parry_accept_time = 2.0, ignore_parry_time = 0.1},
}

local preset_order = {"Professional", "Easier", "Default", "Harder"}  -- Order of presets as they should appear

local save_file_path = "Mr. Boobie\\Easy_Parry.json"

-- Store the last known values
local last_values = {}

local scene = nil
local has_run_initially = false
local threshold = 0.01

local cached_player = nil
local cached_equipment = nil

local function save_configuration()
    local data = {
        parry_accept_time = defaults.parry_accept_time,
        ignore_parry_time = defaults.ignore_parry_time
    }
    local success, err = pcall(json.dump_file, save_file_path, data)
    if not success then
        --log.warn("Error saving configuration: " .. tostring(err))
    end
end

local function load_configuration()
    local status, data = pcall(json.load_file, save_file_path)
    if not status or not data then
        -- Set to default preset on fresh install or if data failed to load
        local default_preset = parry_presets["Default"]  -- Replace "Default" with your desired default preset key
        defaults.parry_accept_time = default_preset.parry_accept_time
        defaults.ignore_parry_time = default_preset.ignore_parry_time
        --log.info("Using default preset for parry settings.")
        return
    end

    if type(data) ~= "table" then
        --log.info("Data is not a table. Using default values.")
        local default_preset = parry_presets["Default"]
        defaults.parry_accept_time = default_preset.parry_accept_time
        defaults.ignore_parry_time = default_preset.ignore_parry_time
        return
    end

    if data.parry_accept_time and data.ignore_parry_time then
        defaults.parry_accept_time = data.parry_accept_time
        defaults.ignore_parry_time = data.ignore_parry_time
    else
        --log.info("Configuration keys are not present in data. Using default values.")
        local default_preset = parry_presets["Default"]
        defaults.parry_accept_time = default_preset.parry_accept_time
        defaults.ignore_parry_time = default_preset.ignore_parry_time
    end
end

local function get_player_equipment()
    if not cached_player or not cached_equipment then
     --   log.info("Cache miss - Manually retrieving player equipment")
        for _, character_id in ipairs(character_ids) do
            local pl = scene:call("findGameObject(System.String)", character_id)
            if pl then
              --  log.info("Found player object: " .. tostring(pl))
                local equip = pl:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerCommonParameter"))
                if equip then
                --    log.info("Found player equipment: " .. tostring(equip))
                    cached_player = pl
                    cached_equipment = equip
                    break
                else
              --      log.info("No equipment found for player object: " .. tostring(pl))
                end
            else
             --   log.info("Player object not found for character ID: " .. character_id)
            end
        end
    else
      --  log.info("Using cached player equipment")
    end

    return cached_equipment
end


local function retrieve_fields_values()
    local scene_manager = sdk.get_native_singleton("via.SceneManager")
    if not scene_manager then
        return
    end

    local scene = sdk.call_native_func(scene_manager, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    if not scene then
    --    log.warn("Scene not found! Cancelling.")
        return
    end

    local pl_head = scene:call("findGameObject(System.String)", "ch0a0z0_head")

    if not pl_head then
        for _, character_id in ipairs(character_ids) do
            pl_head = scene:call("findGameObject(System.String)", character_id)
            if pl_head then
                break
            end
        end
    end
    
    if not pl_head then
        -- log.warn("Player Head not found!")
        return
    end

    local player_equip = pl_head:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerCommonParameter"))
    if not player_equip then
     --   log.warn("Player Equip component not found!")
        return
    end

    local common_param = player_equip:get_field("_PlayerCommonParamUserData")
    local assisted_param = player_equip:get_field("_PlayerCommonParamUserData_Assisted")
    local hardcore_param = player_equip:get_field("_PlayerCommonParamUserData_Hardcore")
    local professional_param = player_equip:get_field("_PlayerCommonParamUserData_Professional")

    -- Retrieve parry-related values
    local function store_initial_values(param)
        if param then
            for key, field_name in pairs(field_mapping) do
                last_values[field_name] = param:get_field(field_name)
            end
        end
    end

    -- (Retrieve common_param, assisted_param, hardcore_param, and professional_param as before)

    store_initial_values(common_param)
    store_initial_values(assisted_param)
    store_initial_values(hardcore_param)
    store_initial_values(professional_param)
end

-- Check if any value has changed by more than the threshold
local function has_values_changed()
    if not scene then return false end

    local player_equip = get_player_equipment()
    if not player_equip then
        return false
    end

    local common_param = player_equip:get_field("_PlayerCommonParamUserData")
    if not common_param then
      --  log.warn("Common Param data not found!")
        return false
    end

    for key, default_value in pairs(defaults) do
        local field_name = field_mapping[key]
        local current_value = common_param:get_field(field_name)
        if not current_value or not last_values[field_name] or math.abs(last_values[field_name] - current_value) > threshold then
         --   log.info(string.format("Value changed for %s: %f -> %f", field_name, last_values[field_name], current_value))
            last_values[field_name] = current_value
            return true
        end
    end
    return false
end

local function update_parry_parameters()

    -- If the player head is not found, try with other character IDs
    local player_equip = get_player_equipment()
    if not player_equip then
        return false
    end
    if player_equip then
        -- Retrieve the different parameter sets for each difficulty level
        local common_param = player_equip:get_field("_PlayerCommonParamUserData")
        local assisted_param = player_equip:get_field("_PlayerCommonParamUserData_Assisted")
        local hardcore_param = player_equip:get_field("_PlayerCommonParamUserData_Hardcore")
        local professional_param = player_equip:get_field("_PlayerCommonParamUserData_Professional")

        -- Function to update nested parry-related fields for a given parameter set
        local update_param = function(param)
            if param then
                local parry_param = param:get_field("_ParryParam")
                if parry_param then
                    parry_param:set_field("_ParryAcceptTime", defaults.parry_accept_time)
                    parry_param:set_field("_IgnoreParryTime", defaults.ignore_parry_time)
                end
            end
        end

        -- Update the nested parry-related fields for each parameter set
        update_param(common_param)
        update_param(assisted_param)
        update_param(hardcore_param)
        update_param(professional_param)
    end
end

local function reset_context_variables()
    -- Reset the flag to allow the initial setup to run again for the new context
    cached_player = nil
    cached_equipment = nil
    has_run_initially = false
    last_values = {}
    --log.info("Resetting context variables")
    -- Clear last known values to ensure they will be reacquired for the new context
    for key, _ in pairs(last_values) do
        last_values[key] = nil
    end
    retrieve_fields_values()
    load_configuration()
end

re.on_script_reset(function()

    reset_context_variables()

end)

load_configuration()
retrieve_fields_values()

re.on_frame(function()

    if has_run_initially and not has_values_changed()  then
     --   log.info("No values have changed. Returning.")
        return
    end

    local scene_manager = sdk.get_native_singleton("via.SceneManager")
    if not scene_manager then
        reset_context_variables()
        return
    end

     scene = sdk.call_native_func(scene_manager, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    if not scene then
        reset_context_variables()
        log.warn("Scene not found! Cancelling.")
        return
    end

    local character_manager = sdk.get_managed_singleton(sdk.game_namespace("CharacterManager"))
    local player_context = character_manager:call("getPlayerContextRef")
    if player_context == nil then
        reset_context_variables()
        return
    end

    -- If the function has not run initially or if the values have changed
    if not has_run_initially or has_values_changed() then
        --log.info("Combat Run Speeds Updating!")
        update_parry_parameters()
        has_run_initially = true
      --  log.info("Updating Parry Params Heavily")
    end
    --local valuesChanged = has_values_changed(scene)
   -- log.info("Combat Run Speed Initialization is "..tostring(has_run_initially).." And have the values changed: "..tostring(valuesChanged))
end)

re.on_draw_ui(function()
    if not scene then
        return
    end

    local changed = false

    if imgui.tree_node("Easy Parry") then
        -- Find the current index of the selected preset
        local selected_preset_index = 1
        for i, key in ipairs(preset_order) do
            if defaults.parry_accept_time == parry_presets[key].parry_accept_time and
                defaults.ignore_parry_time == parry_presets[key].ignore_parry_time then
                selected_preset_index = i
                break
            end
        end

        -- imgui combo to select preset
        changed, selected_preset_index = imgui.combo("Parry Presets", selected_preset_index, preset_order)
        if changed then
            local selected_preset = parry_presets[preset_order[selected_preset_index]]
            defaults.parry_accept_time = selected_preset.parry_accept_time
            defaults.ignore_parry_time = selected_preset.ignore_parry_time

            -- Save the new configuration
            save_configuration()

            -- Apply changes to the game (you might need to call a specific function here)
            update_parry_parameters()
        end

        imgui.tree_pop()
    end
end)

