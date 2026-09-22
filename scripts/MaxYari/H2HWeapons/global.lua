local mp = "scripts/MaxYari/H2HWeapons/"

local I = require('openmw.interfaces')

local settings = require(mp .. "scripts/settings")

-- A global group rather than a player one: the fatigue damage is worked out on the victim, which
-- for an NPC is an NPC script, and only a global section is readable from there.
I.Settings.registerGroup {
    key = settings.GLOBAL_GROUP,
    page = "H2HWeapons",
    l10n = "H2HWeapons",
    name = "settings_group",
    description = "settings_group_description",
    permanentStorage = false,
    order = 0,
    settings = {
        {
            key = "strengthInfluencesHandToHand",
            name = "strength_influences",
            description = "strength_influences_description",
            default = settings.DEFAULTS.strengthInfluencesHandToHand,
            -- The "select" renderer labels each item with the l10n key of its own value, so the
            -- values are the strings below and settings.lua maps them back to the engine's 0/1/2.
            renderer = "select",
            argument = {
                l10n = "H2HWeapons",
                items = { "off", "on", "onExceptWerewolves" },
            },
        },
        {
            key = "handToHandShare",
            name = "hand_to_hand_share",
            description = "hand_to_hand_share_description",
            default = settings.DEFAULTS.handToHandShare,
            renderer = "number",
            argument = { min = 0, max = 1 },
        },
        {
            key = "skillBonusMax",
            name = "skill_bonus_max",
            description = "skill_bonus_max_description",
            default = settings.DEFAULTS.skillBonusMax,
            renderer = "number",
            argument = { min = 0, max = 1 },
        },
        {
            key = "skillBonusMin",
            name = "skill_bonus_min",
            description = "skill_bonus_min_description",
            default = settings.DEFAULTS.skillBonusMin,
            renderer = "number",
            argument = { min = 0, max = 1 },
        },
        {
            key = "skillBonusGrace",
            name = "skill_bonus_grace",
            description = "skill_bonus_grace_description",
            default = settings.DEFAULTS.skillBonusGrace,
            renderer = "number",
            argument = { min = 0, max = 100, integer = true },
        },
        {
            key = "skillBonusFalloff",
            name = "skill_bonus_falloff",
            description = "skill_bonus_falloff_description",
            default = settings.DEFAULTS.skillBonusFalloff,
            renderer = "number",
            argument = { min = 0, max = 100, integer = true },
        },
        {
            key = "showOffHandWeapon",
            name = "show_off_hand_weapon",
            description = "show_off_hand_weapon_description",
            default = settings.DEFAULTS.showOffHandWeapon,
            renderer = "checkbox",
        },
        {
            key = "silenceDrawSound",
            name = "silence_draw_sound",
            description = "silence_draw_sound_description",
            default = settings.DEFAULTS.silenceDrawSound,
            renderer = "checkbox",
        },
    },
}
