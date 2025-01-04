local mod = {luaScriptName="airship-windows.lua"}

function mod.start()
    mod.print("mod.start airship")
    mod.timerInterval = 60

    mod.getBaseInfo()
    
    mod.metrics = {status="",client_id="", err=""}

    mod.metrics.status = "starting"

    local err =  mod.run()
    if err then
        mod.print("Failed to run script: "..err)
    end

    mod.startTimer()
end

function mod.stop()
    mod.print("mod.stop airship")
    local err = mod.stopInstance()
    if err then
        mod.print("Failed to stop instance: "..err)
    end
end

function mod.getBaseInfo()
    local agent = require 'agent'
    local info = agent.info()
    if info then
        mod.info = info
        mod.print(info)
    else
        mod.print("Failed to get base info")
    end
end


function mod.run()
    -- Ensure the install script path is available
    if not mod.installScriptPath then
        local err = mod.fetchInstallScript()
        if err then
            return "load install script error: " .. err
        end
    end

    -- Check and handle status
    local success = false
    while not success do
        local status = mod.status()
        -- if container running check app status , if app exception, try to reinstall 
        if status == "RUNNING" then
            mod.print("Instance is already running.")
            local id, err = mod.getBizId()
            if err then
                mod.print("Running but failed to get bizId: " .. err)
                mod.metrics.err = err
                mod.metrics.status = "exception"
                local err = mod.reinstall() -- Try to reinstall the instance
                if err then
                    mod.print("reinstall error: " .. err)
                else
                    mod.print("Reinstall completed, rechecking status.")
                end
            else
                mod.metrics.status = "running"
                mod.metrics.client_id = id
                success = true
            end
        elseif status == "STOPPED" then
            mod.print("Status STOPPED. Attempting to start the instance.")
            mod.metrics.status = "starting"
            local err = mod.startInstance()
            if err then
                mod.metrics.err = err
                mod.print("start instance error: " .. err)
            else
                success = true -- Only set success if startInstance succeeds
            end

        elseif status == "NONE" then
            mod.print("Status NONE, seems not installed. Attempting to install.")
            mod.metrics.status = "installing"
            local installed, err = mod.install()
            if not installed then
                mod.metrics.err = err
                mod.print("install error: " .. err)
            else
                mod.print("Install completed, rechecking status.")
            end
        else
            mod.print("Status UNKNOWN: " .. tostring(status) .. ". Attempting to reinstall.")
            mod.metrics.status = "re-creating"
            local  err = mod.reinstall()
            if not err then
                mod.metrics.err = err
                mod.print("reinstall error: " .. err)
            else
                mod.print("Reinstall completed, rechecking status.")
            end
        end

        mod.sleep(3)
    end

    -- Attempt to retrieve bizId
    while true do
        local bizId, err = mod.getBizId()
        if err then
            mod.print("Failed to get bizId: " .. err)
            mod.metrics.err = err
        else
            mod.print("Retrieved bizId: " .. bizId)
            break
        end
    end

    return nil
end

function mod.sleep(n)
    os.execute("timeout /t "..n)
 end


function mod.status()
    local agent = require("agent")
    local command = mod.installScriptPath .. " status"
    
    mod.print("status script: "..command)

    local result, err = agent.exec(command, 60)
    if err then
        return "Failed to execute status script: "..err
    end

    if result.status ~= 0 then
        return "Status script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return "Status script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("Status script output: "..result.stdout)
    end

    return mod.parseStatus(result.stdout)
end



function mod.parseStatus(output)
    local _, _, status = string.find(output, "STATUS: %s*(%w+)")
    return string.upper(status)
end


function mod.startInstance()
    local agent = require("agent")
    local command = mod.installScriptPath .. " start"
    
    mod.print("start script: "..command)

    local result, err = agent.exec(command, 1800)
    if err then
        return "Failed to execute start script: "..err
    end

    if result.status ~= 0 then
        return "Start script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return "Start script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("Start script output: "..result.stdout)
    end

    return nil
end

function mod.stopInstance()
    local agent = require("agent")
    local command = mod.installScriptPath .. " stop"
    
    mod.print("stop script: "..command)

    local result, err = agent.exec(command, 1800)
    if err then
        return "Failed to execute stop script: "..err
    end

    if result.status ~= 0 then
        return "stop script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return "stop script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("stop script output: "..result.stdout)
    end

    return nil
end

function mod.install()
    local agent = require("agent")

    local command = mod.installScriptPath .. " install"

    mod.print("install script: "..command)

    local result, err = agent.exec(command, 1800, true)
    if err then
        return false, "Failed to execute install script: "..err
    end

    if result.status ~= 0 then
        return false, "Install script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return false, "Install script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("Install script output: "..result.stdout)
    end

    return true, nil
end

function mod.reinstall()
    local agent = require("agent")
    local command = mod.installScriptPath .. ' reinstall' 
    mod.print("reinstall script: "..command)

    local result, err = agent.exec(command, 1800, true) 
    if err then
        return "Failed to execute reinstall script: "..err
    end

    if result.status ~= 0 then
        return "Reinstall script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return "Reinstall script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("Reinstall script output: "..result.stdout)
    end

    return nil
end


function mod.fetchInstallScript()
    local scriptName = "install-airship.bat"
    local scriptURL = "https://gist.githubusercontent.com/gnasnik/b411f8f5426d926ee4fd74cdb7c8fb06/raw/b0b23df6cd7f512f591e03795a724516f1bf4fef/airship-install.bat"
    -- local scriptPath = mod.info.appDir .. "/" .. scriptName

    -- check script path is absolute or relative to appDir
    local scriptPath
    if string.sub(mod.info.appDir, 1, 1) == "/" or string.sub(mod.info.appDir, 2, 2) == ":" then
        scriptPath = mod.info.appDir .. "/" .. scriptName
    else
        local cwd = io.popen("cd"):read("*l")
        scriptPath = cwd .. "/" .. mod.info.appDir .. "/" .. scriptName
    end
    mod.print("scriptPath: "..scriptPath)

    local err = mod.downloadScript(scriptURL, scriptPath)
    if err then
        mod.print("Failed to download install script: "..err)
        return err
    end

    local agent = require("agent")
    local chmodErr = agent.chmod(scriptPath, "0755")
    if chmodErr then
        mod.print("Failed to chmod install script: "..chmodErr)
        return err
    end

    mod.installScriptPath = scriptPath
end


function mod.downloadScript(url, filePath)
    local http = require("http")
    local client = http.client({timeout=30})

    local request = http.request("GET", url)
    local result, err = client:do_request(request)
    if err then
        return "HTTP request failed: "..err
    end

    if result.code ~= 200 then
        return "HTTP status code "..result.code..", URL: "..url
    end

    local ioutil = require("ioutil")
    local writeErr = ioutil.write_file(filePath, result.body)
    if writeErr then
        return "Failed to write file: "..writeErr
    end

    return nil
end


function mod.getBizId()
    local agent = require("agent")
    local command =  mod.installScriptPath .. ' info'
    mod.print("info script: "..command)
    
    local result, err = agent.exec(command, 30)
    if err then
        return nil, "Failed to execute info script: "..err
    end

    if result.status ~= 0 then
        return nil, "Info script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return nil, "Info script stderr: "..result.stderr
    end

    if result.stdout then
        local bizId = mod.parseBizId(result.stdout)
        if bizId then
            return bizId, nil
        else
            return nil, "Failed to parse bizId from output: "..result.stdout
        end
    end

    return nil, "No output from info script"
end

function mod.parseBizId(output)
    local _, _, bizId = string.find(output, "BOX_ID: %s*(%w+)")
    return bizId
end


function mod.startTimer()
    local timer = require("timer")
    timer.createTimer('monitor', mod.timerInterval, 'onTimerMonitor')
end


function mod.onTimerMonitor()
    mod.print("onTimerMonitor airship.lua")

    if mod.monitorLastActivitTime then
        if os.difftime(os.time(), mod.monitorLastActivitTime) < mod.timerInterval then
            mod.print("Insufficient time to monitor")
            return
        end
    end
    mod.monitorLastActivitTime = os.time()

    local bizId, err = mod.getBizId()
    if err then
        mod.print("Failed to get bizId: "..err)
        mod.sendMetrics({status="failed", client_id="", err=err})

        local installErr = mod.install()
        if installErr then
            mod.print("Install failed again: "..installErr)
            mod.sendMetrics({status="failed", client_id="", err=installErr})
        else
            mod.print("Install succeeded, initiating reinstall.")
            mod.sendMetrics({status="re-creating", client_id=""})
            local reinstallErr = mod.reinstall()
            if reinstallErr then
                mod.print("Reinstall failed: "..reinstallErr)
                mod.sendMetrics({status="failed", client_id="", err=reinstallErr})
            else
                mod.print("Reinstall succeeded, will check bizId next cycle.")
                mod.sendMetrics({status="running", client_id=bizId or ""})
            end
        end
    else
        mod.print("Retrieved bizId: "..bizId)
        mod.sendMetrics({status="running", client_id=bizId})
    end
end


function mod.sendMetrics(metrics)
    local metric = require("metric")
    local json = require("json")
    local jsonString, err = json.encode(metrics)
    if err then
        mod.print("Failed to encode metrics: "..err)
        return
    end

    metric.send(jsonString)
end


function mod.print(msg)
    local logLevel = "info"
    if type(msg) == "table" then
        local tableMsg = "{\n"
        for key, value in pairs(msg) do
            tableMsg = string.format("%s  %s: %s\n", tableMsg, key, tostring(value))
        end
        tableMsg = tableMsg .. "}"
        msg = tableMsg
    end

    -- if type(msg) == "string" then
    --     local err
    --     msg, err = mod.convertToUtf8(msg)
    --     if err then
    --         mod.print("Failed to convert msg to utf8: "..err)
    --     end
    -- end

    print(string.format('time="%s" level=%s lua=%s msg="%s"', os.date("%Y-%m-%dT%H:%M:%S"), logLevel, mod.luaScriptName, tostring(msg)))
end

-- function mod.convertToUtf8(str)
--     local enc = require("iconv").new("UTF-8", "GBK")
--     local converted, err = enc:iconv(str)
--     if not converted then
--         return str
--     end
--     return converted
-- end

return mod
