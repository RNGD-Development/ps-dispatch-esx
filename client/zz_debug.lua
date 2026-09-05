-- TEMPORARY diagnostic. Delete this file once the ESX load path is confirmed.
-- Loaded via the existing 'client/**' glob, so no fxmanifest change is needed.

local function dump(label, value)
    print(('[ps-dispatch:debug] %s = %s'):format(label, tostring(value)))
end

RegisterCommand('dispatchdebug', function()
    print('[ps-dispatch:debug] ─────────── state ───────────')
    dump('Framework.Name()', Framework and Framework.Name())
    dump('GetResourceState(es_extended)', GetResourceState('es_extended'))
    dump('GetResourceState(ox_lib)', GetResourceState('ox_lib'))

    local okExport, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
    dump('getSharedObject ok', okExport)
    dump('esx is table', type(esx) == 'table')

    if type(esx) == 'table' then
        dump('esx.PlayerLoaded', esx.PlayerLoaded)
        local okData, data = pcall(function() return esx.GetPlayerData and esx.GetPlayerData() end)
        dump('esx.GetPlayerData ok', okData)
        if okData and type(data) == 'table' then
            dump('esx job.name', data.job and data.job.name)
            dump('esx job.grade', data.job and data.job.grade)
            dump('esx sex', data.sex)
        else
            dump('esx PlayerData', 'NOT A TABLE')
        end
    end

    local okBridge, bridgeData = pcall(function() return Bridge and Bridge.GetPlayerData() end)
    dump('Bridge.GetPlayerData ok', okBridge)
    if okBridge and type(bridgeData) == 'table' then
        dump('bridge job.name', bridgeData.job and bridgeData.job.name)
        dump('bridge job.type', bridgeData.job and bridgeData.job.type)
    else
        dump('Bridge.GetPlayerData', tostring(bridgeData))
    end

    dump('PlayerData.job.name', PlayerData and PlayerData.job and PlayerData.job.name)
    dump('PlayerData.job.type', PlayerData and PlayerData.job and PlayerData.job.type)
    dump('Config.Jobs', Config and Config.Jobs and table.concat(Config.Jobs, ', '))
    dump('IsOnDuty()', IsOnDuty and IsOnDuty())
    print('[ps-dispatch:debug] ────────────────────────────')
end, false)

-- Did the ESX events actually reach this resource? These print once each.
AddEventHandler('esx:playerLoaded', function()
    print('[ps-dispatch:debug] EVENT esx:playerLoaded RECEIVED')
end)

AddEventHandler('esx:setJob', function(job)
    print(('[ps-dispatch:debug] EVENT esx:setJob RECEIVED (%s)'):format(job and job.name))
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    print('[ps-dispatch:debug] onResourceStart fired')
end)
