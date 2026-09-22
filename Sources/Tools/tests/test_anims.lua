package.path = arg[0]:gsub("[^/]*$", "") .. "?.lua;" .. package.path
local stubs = require("stubs")
local K, R = stubs.findMods()
stubs.addRoot(R); stubs.addRoot(K)

local st = stubs.state
local fails, checks = 0, 0
local function check(ok, msg, extra)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL: " .. msg .. (extra and ("  ["..tostring(extra).."]") or "")) end
end

st.weaponRecords["katar_steel"] = { type = 0, model = "meshes/steel_katar.nif" }
st.weaponRecords["steel dagger"] = { type = 0, model = "meshes/w/w_dagger.nif" }
st.groups = { weapononehand = true, katar = true, kataralt = true, idlekatar = true, idle1s = true }
st.stance = 1

local function key(k, t) st.textKeys[string.lower(k)] = t end
for _, g in ipairs({ "weapononehand", "katar" }) do
    local base = g == "katar" and 0 or 50
    local scale = g == "katar" and 1 or 1
    key(g .. ": slash start", base + 0)
    key(g .. ": slash max attack", base + (g == "katar" and 0.4667 or 0.4667))
    key(g .. ": slash hit", base + (g == "katar" and 0.6 or 0.8))
end

local api = require("scripts.MaxYari.ReAnimation_v3.ReAnimationAPI")
stubs.I.ReAnimation = api.interface
-- the mod's own animation registrations must load without error
local overrides = require("scripts.MaxYari.H2HWeapons.animations")
check(true, "animations.lua loaded")

-- ReAnimation's own one-handed set, registered the way AnimationOverrides.lua does
api.interface.addAttackVariants({
    id = "1hAttacks",
    parentAttackGroupname = "weapononehand",
    armatureType = 1,
    attacks = { slash = { { "weapononehand" }, { "weapononehand1" } },
                chop = { { "weapononehand" }, { "weapononehand1" } } },
})
st.groups.weapononehand1 = true

local function swing()
    st.played = {}
    local o = { startKey = "slash start", startkey = "slash start", stopKey = "slash max attack",
                stopkey = "slash max attack", speed = 2, priority = 7, blendMask = 15 }
    stubs.I.AnimationController.playBlendedAnimation("weapononehand", o)
    local groups = {}
    for _, p in ipairs(st.played) do groups[p.group] = true end
    return groups, o
end

st.equipped = { recordId = "katar_steel" }
local groups, opts = swing()
check(groups["katar"] == true, "a katar swings with the katar animation")
check(groups["weapononehand1"] ~= true, "and ReAnimation's own alternate is stood down")
check(math.abs(opts.speed - 2.0) < 1e-3, "and the parent is re-timed to it", opts.speed)

st.equipped = { recordId = "steel dagger" }
groups = swing()
check(groups["katar"] ~= true, "a dagger does not swing with the katar animation")

print(string.format("\n%d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
