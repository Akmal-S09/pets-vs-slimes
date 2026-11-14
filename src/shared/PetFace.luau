-- PetFace.luau (ModuleScript, shared)
-- Draws a scalable cute pet face (eyes + smile + species features) as children
-- of a coloured circle frame `circ` of diameter S px. Self-contained so it can
-- be used by the HUD (backpack / index) AND the trade UI — identical faces
-- everywhere.

local PetFace = {}

local WHITE = Color3.fromRGB(255, 245, 230)
local INK   = Color3.fromRGB(20, 14, 28)

local function corner(o, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o
end
local function mkF(parent, size, pos, col, tr, z)
	local f = Instance.new("Frame")
	f.Size = size; f.Position = pos; f.BackgroundColor3 = col
	f.BackgroundTransparency = tr or 0; f.BorderSizePixel = 0
	if z then f.ZIndex = z end
	f.Parent = parent
	return f
end

local FACE_PROFILE = {
	blob_slime      = { eye=0.18, mouth=0.30, my=0.55 },
	fire_pup        = { eye=0.20, mouth=0.24, my=0.55 },
	flame_fox       = { eye=0.19, mouth=0.20, my=0.57 },
	shadow_cat      = { eye=0.23, mouth=0.13, my=0.59 },
	frost_bunny     = { eye=0.22, mouth=0.13, my=0.59 },
	mini_dragon     = { eye=0.20, mouth=0.18, my=0.56 },
	storm_hawk      = { eye=0.17, mouth=0.16, my=0.57 },
	crystal_phoenix = { eye=0.21, mouth=0.18, my=0.56 },
	chicken         = { eye=0.17, mouth=0.10, my=0.50 },
	emperor_snake   = { eye=0.18, mouth=0.10, my=0.50 },
}

function PetFace.draw(circ, baseId, col, S, zBase)
	zBase = zBase or 43
	local zF, zE, zP, zS = zBase+1, zBase+2, zBase+3, zBase+4   -- feature / eye / pupil / shine
	local function P(f) return math.max(1, math.floor(f*S + 0.5)) end
	local ex = FACE_PROFILE[baseId] or { eye=0.19, mouth=0.22, my=0.57 }

	-- ── eyes (white, dark pupil, shine) ──
	local eyeD = P(ex.eye)
	local function eye(cx)
		local e = mkF(circ, UDim2.fromOffset(eyeD, eyeD), UDim2.new(cx, -eyeD/2, 0, P(0.30)), WHITE, 0, zE)
		corner(e, eyeD//2)
		local pd = math.max(2, math.floor(eyeD*0.56))
		local p  = mkF(e, UDim2.fromOffset(pd, pd), UDim2.new(0.5,-pd//2,0.5,-pd//2+1), INK, 0, zP)
		corner(p, pd//2)
		if eyeD >= 9 then
			local s = math.max(2, pd//3)
			local sh = mkF(p, UDim2.fromOffset(s,s), UDim2.new(0,1,0,1), WHITE, 0, zS); corner(sh,2)
		end
	end
	eye(0.30); eye(0.70)

	-- ── smile (bottom half of a circle = U) ──
	local mW = P(ex.mouth); local mH = math.max(2, math.floor(mW*0.5))
	local clip = Instance.new("Frame")
	clip.Size = UDim2.fromOffset(mW, mH); clip.AnchorPoint = Vector2.new(0.5,0)
	clip.Position = UDim2.new(0.5,0,0,P(ex.my)); clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true; clip.ZIndex = zE; clip.Parent = circ
	local arc = Instance.new("Frame"); arc.Size = UDim2.fromOffset(mW, mW)
	arc.Position = UDim2.new(0,0,0,-(mW-mH)); arc.BackgroundColor3 = INK
	arc.BorderSizePixel = 0; arc.ZIndex = zE; arc.Parent = clip
	local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1,0); ac.Parent = arc

	-- ── feature helper (rounded rects, can extend above the circle) ──
	local function feat(cx, yf, wf, hf, c, ang, z)
		local w, h = P(wf), P(hf)
		local f = mkF(circ, UDim2.fromOffset(w,h), UDim2.new(cx, -w/2, 0, math.floor(yf*S)), c, 0, z or zF)
		corner(f, math.max(2, math.min(w,h)//2))
		if ang then f.Rotation = ang end
		return f
	end
	local pink   = Color3.fromRGB(248,150,178)
	local dark   = col:Lerp(Color3.new(0,0,0), 0.25)
	local lite   = col:Lerp(WHITE, 0.4)

	if baseId == "shadow_cat" then
		feat(0.22,-0.04,0.26,0.34, col, -22); feat(0.78,-0.04,0.26,0.34, col, 22)
		feat(0.22, 0.00,0.13,0.20, Color3.fromRGB(190,110,245), -22)
		feat(0.78, 0.00,0.13,0.20, Color3.fromRGB(190,110,245),  22)
		feat(0.50, 0.49,0.11,0.08, Color3.fromRGB(245,140,165), nil, zP)
	elseif baseId == "frost_bunny" then
		feat(0.34,-0.30,0.17,0.52, col); feat(0.66,-0.30,0.17,0.52, col)
		feat(0.34,-0.24,0.09,0.40, Color3.fromRGB(248,205,228)); feat(0.66,-0.24,0.09,0.40, Color3.fromRGB(248,205,228))
		feat(0.16, 0.52,0.16,0.13, Color3.fromRGB(250,185,208), nil, zF); feat(0.84,0.52,0.16,0.13, Color3.fromRGB(250,185,208), nil, zF)
		feat(0.50, 0.49,0.09,0.07, pink, nil, zP)
	elseif baseId == "mini_dragon" then
		feat(0.30,-0.10,0.13,0.26, Color3.fromRGB(244,205,150), -28); feat(0.70,-0.10,0.13,0.26, Color3.fromRGB(244,205,150), 28)
		feat(0.04, 0.28,0.20,0.30, dark, -18); feat(0.96,0.28,0.20,0.30, dark, 18)
	elseif baseId == "fire_pup" then
		feat(0.16,-0.05,0.24,0.24, col); feat(0.84,-0.05,0.24,0.24, col)
		feat(0.16,-0.01,0.15,0.15, dark); feat(0.84,-0.01,0.15,0.15, dark)
		feat(0.50, 0.50,0.09,0.07, Color3.fromRGB(40,22,16), nil, zP)
	elseif baseId == "flame_fox" then
		feat(0.14,-0.04,0.18,0.28, col, -22); feat(0.86,-0.04,0.18,0.28, col, 22)
		feat(0.14, 0.00,0.10,0.18, lite, -22); feat(0.86,0.00,0.10,0.18, lite, 22)
	elseif baseId == "storm_hawk" then
		feat(0.30,-0.04,0.24,0.12, col, -16); feat(0.70,-0.04,0.24,0.12, col, 16)
		feat(0.50, 0.46,0.13,0.11, Color3.fromRGB(255,200,40), 45, zP)  -- beak (diamond)
	elseif baseId == "crystal_phoenix" then
		local gem = feat(0.50,-0.10,0.16,0.18, Color3.fromRGB(255,95,215), nil, zF); corner(gem, P(0.04))
		feat(0.08, 0.12,0.18,0.12, lite, -20); feat(0.92,0.12,0.18,0.12, lite, 20)
	elseif baseId == "blob_slime" then
		feat(0.34,-0.16,0.07,0.20, col, -12); feat(0.66,-0.16,0.07,0.20, col, 12)
		feat(0.34,-0.20,0.11,0.10, col); feat(0.66,-0.20,0.11,0.10, col)
	elseif baseId == "chicken" then
		feat(0.42,-0.10,0.14,0.16, Color3.fromRGB(228,55,55))   -- red comb
		feat(0.56,-0.12,0.10,0.13, Color3.fromRGB(228,55,55))
		feat(0.50, 0.50,0.13,0.10, Color3.fromRGB(255,170,40), nil, zP)  -- beak
	elseif baseId == "emperor_snake" then
		feat(0.50,-0.16,0.40,0.10, Color3.fromRGB(255,212,60))  -- gold halo bar
		feat(0.06, 0.28,0.18,0.34, Color3.fromRGB(255,218,80), -18)  -- gold wings
		feat(0.94, 0.28,0.18,0.34, Color3.fromRGB(255,218,80),  18)
		feat(0.50, 0.50,0.11,0.09, Color3.fromRGB(255,175,45), nil, zP)  -- beak
	end
end

return PetFace

