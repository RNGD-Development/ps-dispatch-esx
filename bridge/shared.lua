-- ═══════════════════════════════════════════════════════════════════════════
--  Framework detection (shared)
-- ═══════════════════════════════════════════════════════════════════════════
-- ESX bridge contributed by RNGD-Development. See CREDITS.md.
--
-- ps-dispatch was written against QBCore/QBX. This bridge adds ESX Legacy as a
-- first-class framework WITHOUT touching the internal data shapes the rest of
-- the resource is built on: whichever framework is running, the bridge hands
-- the existing code the player table it already expects.
--
-- Detection is automatic — there is no `Config.Core` switch to get wrong. The
-- active framework is whichever of the three core resources is up. QB/QBX are
-- checked first so nothing changes for servers that already run this resource.
--
-- Resolution is lazy and cached: ps-dispatch may well start before the core
-- resource does, so answering "which framework?" once at file load would be a
-- coin flip. Nothing here is needed until a player exists, by which time every
-- core resource is long started.

Framework = Framework or {}

--- Core resources, in resolution order. First one up wins.
local CORES = {
    { name = 'qbx', resource = 'qbx_core' },
    { name = 'qb',  resource = 'qb-core' },
    { name = 'esx', resource = 'es_extended' },
}

local resolved = nil

---@param resource string
---@return boolean
local function isUp(resource)
    local state = GetResourceState(resource)
    -- 'starting' counts: during a server boot the core may still be coming up
    -- when the first lookup happens, and it is unambiguously the framework.
    return state == 'started' or state == 'starting'
end

--- Active framework: 'qbx' | 'qb' | 'esx' | nil (standalone / not up yet).
---@return string|nil
function Framework.Name()
    if resolved then return resolved end
    for i = 1, #CORES do
        if isUp(CORES[i].resource) then
            resolved = CORES[i].name
            return resolved
        end
    end
    return nil
end

---@return boolean
function Framework.IsESX()
    return Framework.Name() == 'esx'
end

---@return boolean
function Framework.IsQB()
    local name = Framework.Name()
    return name == 'qb' or name == 'qbx'
end

--- The `job.type` the rest of the resource gates on ('leo' / 'ems' / ...).
---
--- QBCore jobs carry a type of their own; ESX jobs do not, so one is derived
--- from Config.ESXJobTypes. A job that isn't in that map keeps its own name as
--- its type, which means it simply never matches the leo/ems special-casing
--- rather than being wrongly swept into it.
---@param jobName string|nil
---@return string
function Framework.JobType(jobName)
    if type(jobName) ~= 'string' or jobName == '' then return 'civilian' end
    local map = Config and Config.ESXJobTypes
    local mapped = type(map) == 'table' and map[jobName] or nil
    if type(mapped) == 'string' and mapped ~= '' then return mapped end
    return jobName
end
