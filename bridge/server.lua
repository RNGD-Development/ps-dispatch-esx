-- ═══════════════════════════════════════════════════════════════════════════
--  Framework bridge (server)
-- ═══════════════════════════════════════════════════════════════════════════
-- ESX bridge contributed by RNGD-Development. See CREDITS.md.
--
-- Server-side counterpart to bridge/client.lua. Two things are needed here:
-- the set of connected players (to filter who a call is broadcast to) and one
-- player by source (to check an incident-declaring supervisor's grade and to
-- name them on everyone else's board).
--
-- Both are handed back in the QBCore shape the existing server code already
-- reads — `{ PlayerData = { citizenid, charinfo, metadata, job } }` — so the
-- call sites in server/main.lua and server/incidents.lua only ever needed the
-- accessor swapped, not their logic rewritten. On QB/QBX the objects returned
-- ARE the QBCore objects, untouched.

Bridge = Bridge or {}

local qbCore = nil
local esxCore = nil

--- The QBCore/QBX core object, or nil when QB isn't the active framework.
---@return table|nil
function Bridge.GetCoreObject()
    if qbCore then return qbCore end
    if not Framework.IsQB() then return nil end
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
    if type(ESX) == 'table' then
        esxCore = ESX
        return esxCore
    end
    local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok and type(obj) == 'table' then esxCore = obj end
    return esxCore
end

--- Can jobs be told apart at all? Every caller falls back to the old
--- broadcast-to-everyone behaviour when this is false, exactly as the original
--- `not QBCore` guard did on a standalone server.
---@return boolean
function Bridge.Available()
    if Framework.IsESX() then return getESX() ~= nil end
    return Bridge.GetCoreObject() ~= nil
end

-- ── ESX identity ────────────────────────────────────────────────────────────
-- ESX Legacy keeps a character's real name in the `users` table and does not
-- reliably carry it on the xPlayer object (that depends on esx_identity and on
-- multichar being in play), so it is read from the database directly. The
-- stock schema has both columns, so this needs no migration and no config.
--
-- Reading the users table for the name is an idea taken from the community
-- fork at github.com/Sixxenik/ps-dispatch-esx — credited in CREDITS.md. None
-- of that fork's code is used here.

--- identifier -> { firstname, lastname }
local identities = {}
--- identifier -> true while a lookup is in flight, so a burst of broadcasts
--- for an uncached player queues one query rather than one per alert.
local identityPending = {}
--- source -> identifier, purely so a disconnect can drop the cached name.
local identitySources = {}

--- One users-table lookup. Returns nil on any failure (no oxmysql, no row,
--- query error) — every caller degrades to a nameless unit rather than erroring.
---@param identifier string
---@return table|nil
local function queryIdentity(identifier)
    local p = promise.new()
    local settled = false
    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value)
    end

    local ok = pcall(function()
        exports.oxmysql:single('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier },
            function(row) settle(row) end)
    end)
    if not ok then return nil end

    -- The callback form is used rather than an awaitable export because it has
    -- been stable across every oxmysql version; the timeout is what keeps a
    -- silent failure from parking this coroutine forever.
    SetTimeout(5000, function() settle(nil) end)

    local row = Citizen.Await(p)
    if type(row) ~= 'table' then return nil end
    return {
        firstname = type(row.firstname) == 'string' and row.firstname or nil,
        lastname = type(row.lastname) == 'string' and row.lastname or nil,
    }
end

--- Cached name for an identifier, fetching it once if needed.
--- Only call from a coroutine — `cached` alone is the synchronous accessor.
---@param identifier string|nil
---@return table
local function identityFor(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    local hit = identities[identifier]
    if hit then return hit end

    identityPending[identifier] = true
    local fetched = queryIdentity(identifier)
    identityPending[identifier] = nil
    -- Only a real answer is cached. A failed lookup (oxmysql not up yet, row
    -- not written yet) must stay retryable, or a player unlucky with timing
    -- would be nameless for the rest of the session.
    if fetched and (fetched.firstname or fetched.lastname) then
        identities[identifier] = fetched
        return fetched
    end
    return {}
end

--- Whatever is already known, without ever blocking. When the cache is cold a
--- fetch is kicked off for next time and ESX's own name is used meanwhile —
--- xPlayer.getName() is the character name on servers running esx_identity and
--- the account name otherwise, which is still better than an unnamed unit.
---@param xPlayer table
---@return table
local function cachedIdentity(xPlayer)
    local identifier = xPlayer and xPlayer.identifier
    if type(identifier) ~= 'string' then return {} end

    local hit = identities[identifier]
    if hit then return hit end

    if not identityPending[identifier] then
        identityPending[identifier] = true
        CreateThread(function() identityFor(identifier) end)
    end

    local name = nil
    if type(xPlayer.getName) == 'function' then
        local ok, result = pcall(xPlayer.getName, xPlayer)
        if ok and type(result) == 'string' then name = result end
    end
    name = name or xPlayer.name
    if type(name) ~= 'string' or name == '' then return {} end

    local first, last = name:match('^(%S+)%s+(.+)$')
    return { firstname = first or name, lastname = last }
end

-- A logged-out player's name is dead weight; the next login re-reads it.
-- Hung off the native event rather than `esx:playerDropped`, whose payload has
-- differed between ESX Legacy versions.
AddEventHandler('playerDropped', function()
    local identifier = identitySources[source]
    identitySources[source] = nil
    if type(identifier) == 'string' then identities[identifier] = nil end
end)

-- ── Server-owner hooks ──────────────────────────────────────────────────────
-- ESX Legacy has no generic duty concept and no callsigns. Both are therefore
-- questions only the server owner can answer; see shared/config.lua.

---@param identifier string|nil
---@param xPlayer table|nil
---@return boolean
local function esxOnDuty(identifier, xPlayer)
    local hook = Config and Config.ESXDutyCheck
    if type(hook) ~= 'function' then return true end
    local ok, result = pcall(hook, identifier, xPlayer)
    if not ok then return true end
    return result ~= false
end

---@param identifier string|nil
---@param xPlayer table|nil
---@return string|nil
local function esxCallsign(identifier, xPlayer)
    local hook = Config and Config.ESXGetCallsign
    if type(hook) ~= 'function' then return nil end
    local ok, result = pcall(hook, identifier, xPlayer)
    if ok and type(result) == 'string' and result ~= '' then return result end
    return nil
end

-- ── Normalisation ───────────────────────────────────────────────────────────

--- An xPlayer wrapped in the QBCore-shaped object the rest of the server code
--- reads. `job.grade` is deliberately a table: ESX stores a plain integer, but
--- the incident code reads both `grade.level` and `grade.name`, and it should
--- not have to know which framework it is talking to.
---@param xPlayer table
---@return table
local function wrapESXPlayer(xPlayer)
    local job = xPlayer.job or {}
    local identifier = xPlayer.identifier
    local identity = cachedIdentity(xPlayer)

    -- Also recorded here, not only on esx:playerLoaded: a resource restart
    -- mid-session misses that event for everyone already in world.
    if xPlayer.source and type(identifier) == 'string' then
        identitySources[xPlayer.source] = identifier
    end

    return {
        source = xPlayer.source,
        PlayerData = {
            source = xPlayer.source,
            citizenid = identifier,
            charinfo = {
                firstname = identity.firstname,
                lastname = identity.lastname,
            },
            metadata = {
                callsign = esxCallsign(identifier, xPlayer),
            },
            job = {
                name = job.name,
                label = job.label,
                type = Framework.JobType(job.name),
                grade = {
                    level = tonumber(job.grade) or 0,
                    name = job.grade_name,
                    label = job.grade_label,
                },
                onduty = esxOnDuty(identifier, xPlayer),
            },
        },
    }
end

--- Every connected player, keyed by source, in the QBCore player-object shape.
---@return table
function Bridge.GetPlayers()
    if Framework.IsESX() then
        local players = {}
        local esx = getESX()
        if not esx then return players end
        local ids = esx.GetPlayers()
        if type(ids) ~= 'table' then return players end
        for i = 1, #ids do
            local src = ids[i]
            local xPlayer = esx.GetPlayerFromId(src)
            if xPlayer then players[src] = wrapESXPlayer(xPlayer) end
        end
        return players
    end

    local core = Bridge.GetCoreObject()
    if not core then return {} end
    return core.Functions.GetQBPlayers() or {}
end

--- One player by source, in the QBCore player-object shape, or nil.
---@param src number
---@return table|nil
function Bridge.GetPlayer(src)
    if Framework.IsESX() then
        local esx = getESX()
        if not esx then return nil end
        local xPlayer = esx.GetPlayerFromId(src)
        if not xPlayer then return nil end
        return wrapESXPlayer(xPlayer)
    end

    local core = Bridge.GetCoreObject()
    if not core then return nil end
    return core.Functions.GetPlayer(src)
end

-- ── Client identity feed ────────────────────────────────────────────────────
-- The ESX client cannot answer "what is my character called, what is my
-- callsign, am I on duty" on its own, so it asks here on load and on every job
-- change. Cheap and rare — twice a shift, not once an alert.

lib.callback.register('ps-dispatch:callback:esx:playerInfo', function(source)
    if not Framework.IsESX() then return nil end
    local esx = getESX()
    if not esx then return nil end
    local xPlayer = esx.GetPlayerFromId(source)
    if not xPlayer then return nil end

    local identifier = xPlayer.identifier
    -- Awaiting here is fine and is the point: this is the one path that may
    -- block, and it runs off the hot path entirely.
    local identity = identityFor(identifier)
    if not identity.firstname and not identity.lastname then
        identity = cachedIdentity(xPlayer)
    end

    return {
        identifier = identifier,
        firstname = identity.firstname,
        lastname = identity.lastname,
        callsign = esxCallsign(identifier, xPlayer),
        onduty = esxOnDuty(identifier, xPlayer),
    }
end)

-- Warm the cache the moment a character is in world, so the first incident
-- declared in a session is already named correctly.
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    if not Framework.IsESX() then return end
    local identifier = xPlayer and xPlayer.identifier
    if type(identifier) ~= 'string' then return end
    if playerId then identitySources[playerId] = identifier end
    CreateThread(function() identityFor(identifier) end)
end)
