-- Which merchants sell which of this mod's spells: [spell id] = { NPC record ids }.
--
-- This file is the whole of the decision; traders.lua only carries it out. Ids are matched without
-- regard to case, and one that is not in the game - Tamriel Rebuilt's without Tamriel Rebuilt - is
-- simply never met.
local U = require("scripts/MaxYari/H2HWeapons/scripts/uniques")

return {
    -- Bound Fist: half of every spell merchant who sells Bound Dagger or Bound Mace, about one per
    -- town, across the factions that sell them. Tamriel Rebuilt's priests mostly sell Bound Mace, so
    -- the blunt knuckledusters sit well with them.
    [U.BOUND_FIST_SPELL] = {
        -- Morrowind.esm
        "masalinie merian",           -- Balmora, Guild of Mages
        "heem_la",                    -- Ald-ruhn, Guild of Mages
        "diren vendu",                -- Tel Mora, Tower Services (Telvanni)
        "urtiso faryon",              -- Sadrith Mora, Urtiso Faryon: Sorcerer (Telvanni)

        -- TR_Mainland.esm: Temple
        "TR_m7_Traynili Rovel",       -- Narsis, Eight-Bones Temple
        "TR_m7_Furen Hlavel",         -- Othmura, Temple
        "TR_m3_Farvs Valaro",         -- Vhul, Moss Market: Shrine of St. Veloth
        "TR_m7_Valara Filansi",       -- Ald Iuval, Temple
        -- Imperial Cult
        "TR_m3_Felmo Ilveroth",       -- Old Ebonheart, Grand Chapel of Talos
        "TR_m1_Leobert Velain",       -- Firewatch, Grand Chapel of Akatosh
        "TR_m2_Cantorius Tramel",     -- Helnim, Chapel of Kynareth
        "TR_m4_Valrik",               -- Bal Foyen, Chapel of Mara
        -- Mages Guild
        "TR_m7_Waterfall",            -- Narsis, Guild of Mages: Chambers of Summoning
        "TR_m3_Elvilde",              -- Old Ebonheart, Guild of Mages
        "TR_m2_Fedris_Nelavyn",       -- Akamora, Guild of Mages
        "TR_m3_Lorviel",              -- Almas Thirr, Guild of Mages
        "TR_m3_Celanya",              -- Othrenis, Zebba's Pate Cornerclub
        -- the rest
        "TR_m3_Qowenfaare",           -- Nanaav, Scriptorium (House Indoril)
        "TR_m1_Nilena_Othril",        -- Gah Sadrith, Market (Telvanni)
        "TR_m3_Burahk gra-Omphub",    -- Nanaav, Black Hand Hall (Morag Tong)
        "TR_m3_Galoro Sevlor",        -- Dondril, Galoro Sevlor's House (witchhunter)

        -- Tamriel_Data.esm
        "T_Aid_CustomSpellsGuy",      -- John Conjuration. Of course.
    },
}
