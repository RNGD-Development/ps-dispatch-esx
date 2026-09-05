-- ═══════════════════════════════════════════════════════════════════════════
--  Framework bridge (client)
-- ═══════════════════════════════════════════════════════════════════════════
-- ESX bridge contributed by RNGD-Development. See CREDITS.md.
--
-- Everything the client files need from a framework goes through here, so the
-- rest of the resource never has to ask which one is running. On QB/QBX every
-- call is a thin pass-through to QBCore.Functions — behaviour is unchanged.
--
-- The shape this hands back is the one ps-dispatch already uses internally:
--
--   { charinfo = { firstname, lastname }, metadata = { callsign },
--     citizenid, job = { type, name, label } }
--
-- ESX has no equivalent of three of those fields, so they are resolved
-- server-side (bridge/server.lua) and cached here:
--   · firstname / lastname → SELECT from the stock `users` table
--   · callsign             → Config.ESXGetCallsign hook (nil by default)
--   · on/off duty          → Config.ESXDutyCheck hook (always on by default)
-- `citizenid` becomes the ESX identifier: it is only ever used as an opaque
-- key for unit matching, never parsed.

Bridge = Bridge or {}

-- ── Core objects ────────────────────────────────────────────────────────────

local qbCore = nil
local esxCore = nil

--- The QBCore/QBX core object, or nil when QB isn't the active framework.
--- Resolved through pcall: on an ESX server the export does not exist, and the
--- unguarded call this replaces took the whole client script down with it.
---@return table|nil
function Bridge.GetCoreObject()
    if qbCore then return qbCore end
    if not Framework.IsQB() then return nil end
    -- qb-core first: that is what every existing install resolves today, and
    -- QBX ships a qb-core compatibility resource on most setups.
    for _, resource in ipairs({ 'qb-core', 'qbx_core' }) do
        if GetResourceState(resource) == 'started' then
            local ok, core = pcall(function() return exports[resource]:GetCoreObject() end)
            if ok and type(core) == 'table' then
                qbCore = core
                return qbCore
            end
        end
    end
    return nil
end

--- The ESX shared object, or nil when ESX isn't the active framework.
---@return table|nil
local function getESX()
    if esxCore then return esxCore end
    if not Framework.IsESX() then return nil end
    -- A server that imports es_extended's own imports.lua elsewhere already
    -- has the global; otherwise ask for it. The export is the supported route
    -- in ESX Legacy 1.9+ and needs no fxmanifest dependency, which is what
    -- keeps this resource loadable on servers with no ESX installed at all.
    if type(ESX) == 'table' then
        esxCore = ESX
        return esxCore
    end
    local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok and type(obj) == 'table' then esxCore = obj end
    return esxCore
end

-- ── ESX identity cache ──────────────────────────────────────────────────────
-- Filled from the server on player load and job change (see RefreshPlayerInfo).
-- Cached rather than fetched on demand because the readers below sit on hot
-- paths — the gender lookup runs once per alert sent — and a callback round
-- trip there would be absurd.

local esxIdentity = {}
local esxOnDuty = true

--- Pull name / callsign / duty state for this player from the server.
--- No-op off ESX. Must be called from a coroutine (it awaits a callback);
--- every caller is an event handler or a thread, which are coroutines already.
function Bridge.RefreshPlayerInfo()
    if not Framework.IsESX() then return end
    local info = lib.callback.await('ps-dispatch:callback:esx:playerInfo', false)
    if type(info) ~= 'table' then return end
    esxIdentity = info
    if type(info.onduty) == 'boolean' then esxOnDuty = info.onduty end
end

-- Escape hatch for servers with a duty system of their own: flipping duty
-- normally has no ESX event to hang off, so a resource that owns that state
-- can push it here directly instead of waiting for the next job update.
--   TriggerClientEvent('ps-dispatch:client:setDuty', src, true)
RegisterNetEvent('ps-dispatch:client:setDuty', function(onDuty)
    if type(onDuty) == 'boolean' then esxOnDuty = onDuty end
end)

-- ── Player data ─────────────────────────────────────────────────────────────

--- ESX client player data, normalised into ps-dispatch's internal shape.
---@return table
local function esxPlayerData()
    local esx = getESX()
    local data = (esx and esx.GetPlayerData and esx.GetPlayerData()) or {}
    local job = data.job or {}
    local ident = esxIdentity or {}

    return {
        charinfo = {
            firstname = ident.firstname or '',
            lastname = ident.lastname or '',
            -- ESX Legacy's stock `users` table has no phone column that is
            -- portable across setups, so this stays nil — exactly as it
            -- already is on QBCore, where setupDispatch never copied it.
            phone = nil,
            gender = (data.sex == 'f' or data.sex == 'F' or data.sex == 1) and 1 or 0,
        },
        metadata = {
            callsign = ident.callsign,
        },
        citizenid = ident.identifier or data.identifier,
        job = {
            type = Framework.JobType(job.name),
            name = job.name,
            label = job.label,
            -- Grade as a table even though ESX stores a plain integer: the
            -- incident code reads `grade.level or grade` and `grade.name`, so
            -- normalising here is what lets that code stay framework-blind.
            grade = {
                level = tonumber(job.grade) or 0,
                name = job.grade_name,
                label = job.grade_label,
            },
            onduty = esxOnDuty,
        },
    }
end

--- Current player data in ps-dispatch's internal shape, or nil when the player
--- isn't loaded yet.
---@return table|nil
function Bridge.GetPlayerData()
    if Framework.IsESX() then return esxPlayerData() end
    local core = Bridge.GetCoreObject()
    if not core then return nil end
    return core.Functions.GetPlayerData()
end

--- 0 male · 1 female, matching QBCore's charinfo.gender.
---@return number
function Bridge.GetGender()
    if Framework.IsESX() then
        local esx = getESX()
        local data = (esx and esx.GetPlayerData and esx.GetPlayerData()) or {}
        return (data.sex == 'f' or data.sex == 'F' or data.sex == 1) and 1 or 0
    end
    local core = Bridge.GetCoreObject()
    local data = core and core.Functions.GetPlayerData()
    local charinfo = data and data.charinfo
    return (charinfo and charinfo.gender) or 0
end

--- Restrained? Blocks 911/311 calls.
--- ESX Legacy has no core handcuff flag, so the two state-bag keys the common
--- ESX cuff scripts set are checked and anything else reads as free. A server
--- whose cuff script uses neither simply keeps the pre-existing "can call"
--- behaviour rather than getting a wrong answer.
---@return boolean
function Bridge.IsHandcuffed()
    if Framework.IsESX() then
        local state = LocalPlayer and LocalPlayer.state
        if state and (state.handcuffed == true or state.isHandcuffed == true) then
            return true
        end
        return false
    end
    local core = Bridge.GetCoreObject()
    local data = core and core.Functions.GetPlayerData()
    return (data and data.metadata and data.metadata.ishandcuffed) and true or false
end

--- Duty state only — whether duty is enforced at all is Config.OnDutyOnly,
--- which stays where it was in client/utils.lua.
---@return boolean
function Bridge.IsOnDuty()
    if Framework.IsESX() then return esxOnDuty end
    local core = Bridge.GetCoreObject()
    if not core then return true end
    local data = core.Functions.GetPlayerData()
    return (data and data.job and data.job.onduty) and true or false
end

--- Does the player carry this item? Used for the phone requirement.
---@param item string
---@return boolean
function Bridge.HasItem(item)
    if type(item) ~= 'string' or item == '' then return false end

    if Framework.IsQB() then
        -- Left exactly as it was: qb-core already routes this through
        -- ox_inventory itself where that is installed.
        local core = Bridge.GetCoreObject()
        if core and core.Functions and core.Functions.HasItem then
            return core.Functions.HasItem(item) and true or false
        end
        return false
    end

    -- ox_inventory replaces ESX's own inventory wholesale, so it has to be
    -- asked first — the ESX player data still carries an `inventory` table on
    -- such servers, but it is empty and would answer "no phone" forever.
    if GetResourceState('ox_inventory') == 'started' then
        local ok, count = pcall(function() return exports.ox_inventory:GetItemCount(item) end)
        if ok then return (tonumber(count) or 0) > 0 end
    end

    local esx = getESX()
    if not esx then return false end

    if type(esx.SearchInventory) == 'function' then
        local ok, result = pcall(esx.SearchInventory, item)
        if ok and result ~= nil then
            if type(result) == 'number' then return result > 0 end
            if type(result) == 'table' then return (tonumber(result.count) or 0) > 0 end
        end
    end

    -- Stock ESX fallback: the client's own inventory array.
    local data = (esx.GetPlayerData and esx.GetPlayerData()) or {}
    local inventory = data.inventory
    if type(inventory) ~= 'table' then return false end
    for i = 1, #inventory do
        local entry = inventory[i]
        if entry and entry.name == item and (tonumber(entry.count) or 0) > 0 then
            return true
        end
    end
    return false
end
