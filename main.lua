local function FetchEquippedUnits()
    EquippedUUIDs = {}
    
    local function extractUUIDs(str, sourceName)
        if type(str) ~= "string" then return end
        for uuid in string.gmatch(str, "({%x+%-%x+%-%x+%-%x+%-%x+})") do
            if not table.find(EquippedUUIDs, uuid) then
                table.insert(EquippedUUIDs, uuid)
            end
        end
    end

    local function scanObject(obj, depth)
        if depth > 10 then return end -- Prevent infinite loops
        if not obj then return end
        
        -- Scan Name
        extractUUIDs(obj.Name)
        
        -- Scan Values
        if obj:IsA("StringValue") or obj:IsA("IntValue") then
            extractUUIDs(tostring(obj.Value))
        elseif obj:IsA("TextLabel") or obj:IsA("TextBox") or obj:IsA("TextButton") then
            extractUUIDs(obj.Text)
        end
        
        -- Scan Attributes
        for k, v in pairs(obj:GetAttributes()) do
            extractUUIDs(tostring(v))
        end

        for _, child in ipairs(obj:GetChildren()) do
            scanObject(child, depth + 1)
        end
    end

    -- 1. Scan PlayerGui
    scanObject(LocalPlayer.PlayerGui, 1)
    -- 2. Scan ReplicatedStorage
    scanObject(ReplicatedStorage, 1)
    -- 3. Scan Workspace _UNITS (if already placed)
    scanObject(workspace:FindFirstChild("_UNITS"), 1)
    
    -- Filter out quest IDs if possible (usually they don't have specific names, but we can try to only keep ones that look like units)
    -- Actually, let's just use what we found.
end
