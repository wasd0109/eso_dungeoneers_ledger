-- Translation template. Copy the entries you want to translate from lang/en.lua into this table,
-- keeping the string ids and any %s / %d placeholders (in the same order). Missing entries stay English.
local strings =
{
    -- SI_DUNGEONEERSLEDGER_SETTING_SHOW_COMPLETION = "...",
}

for stringId, text in pairs(strings) do
    SafeAddString(_G[stringId], text, 1)
end
