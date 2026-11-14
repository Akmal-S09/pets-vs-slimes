-- LeaderboardMonuments.server.luau
-- Every 30 seconds reads all player data and updates the 3 spawn monuments.

local Players    = game:GetService("Players")
local PlayerData = require(script.Parent.PlayerData)

-- How to format large numbers: 1234567 → "1.23M"
local function fmt(n)
	n = n or 0
	if n >= 1000000 then return string.format("%.2fM", n/1000000)
	elseif n >= 1000 then return string.format("%.1fK", n/1000)
	else return tostring(math.floor(n)) end
end

-- Find all monument signs in workspace
local function findSigns()
	local signs = {}
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name:sub(1,9) == "Monument_" then
			for _, child in ipairs(obj:GetDescendants()) do
				if child.Name:sub(1,7) == "LBSign_" then
					table.insert(signs, child)
				end
			end
		end
	end
	return signs
end

-- Sort all online players by a given field and return top-N entries
local function topPlayers(attr, n)
	local entries = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local ok, d = pcall(PlayerData.get, plr)
		if ok and d then
			table.insert(entries, { name=plr.Name, val=d[attr] or 0 })
		end
	end
	table.sort(entries, function(a,b) return a.val > b.val end)
	local top = {}
	for i = 1, math.min(n, #entries) do top[i] = entries[i] end
	return top
end

local function updateMonuments()
	local signs = findSigns()
	for _, sign in ipairs(signs) do
		local attr = sign:GetAttribute("MonumentAttr")
		if not attr then continue end
		local top = topPlayers(attr, 5)

		-- Group every Row label under this sign by row number (boards are
		-- double-sided, so there are two "Row1" labels, etc.)
		local rowLabels = {}
		for _, desc in ipairs(sign:GetDescendants()) do
			if desc:IsA("TextLabel") and desc.Name:sub(1,3) == "Row" then
				local n = tonumber(desc.Name:sub(4))
				if n then
					rowLabels[n] = rowLabels[n] or {}
					table.insert(rowLabels[n], desc)
				end
			end
		end

		for row = 1, 5 do
			local e   = top[row]
			local txt = e and (row..".  "..e.name.."  — "..fmt(e.val)) or (row..".  —")
			local col = e and (
				    row == 1 and Color3.fromRGB(255,210,55)
				 or row == 2 and Color3.fromRGB(210,210,210)
				 or row == 3 and Color3.fromRGB(200,140,80)
				 or Color3.fromRGB(180,180,200)
			) or Color3.fromRGB(100,100,120)
			for _, rl in ipairs(rowLabels[row] or {}) do
				rl.Text = txt; rl.TextColor3 = col
			end
		end
	end
end

-- Wait for WorldSetup to build the monuments first (retry until they exist)
for _ = 1, 20 do
	if #findSigns() > 0 then break end
	task.wait(1)
end

-- Initial update
updateMonuments()

-- Then refresh every 8 seconds
while true do
	task.wait(8)
	updateMonuments()
end

