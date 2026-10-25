-- Debounced work with a controllable timer.
test("debounce: a burst of calls runs the function once, 150 ms after the first call", function()
    local w = Boot()
    local runs = 0
    for _ = 1, 25 do w.DL.Debounce("k", function() runs = runs + 1 end) end
    eq(w:pendingTimers(), 1, "one timer for the whole burst")
    w:advance(149); eq(runs, 0)
    w:advance(1); eq(runs, 1)
    w:advance(1000); eq(runs, 1)
    eq(w:pendingTimers(), 0)
end)

test("debounce: after it ran, the next call schedules again; different keys are independent", function()
    local w = Boot()
    local a, b = 0, 0
    w.DL.Debounce("a", function() a = a + 1 end)
    w.DL.Debounce("b", function() b = b + 1 end)
    eq(w:pendingTimers(), 2)
    w:advance(150); eq(a, 1); eq(b, 1)
    w.DL.Debounce("a", function() a = a + 1 end)
    w:advance(150); eq(a, 2); eq(b, 1)
end)

test("debounce: a failing function is reported, does not break later runs, and the key is released", function()
    local w = Boot()
    w.DL.Debounce("boom", function() error("bad") end)
    w:advance(150)
    w.DL.SetDebug(true)
    ok(w:chatText():find("error in boom: ", 1, true), w:chatText())
    local ran = false
    w.DL.Debounce("boom", function() ran = true end)
    w:advance(150)
    ok(ran, "key stayed blocked after an error")
end)

test("debounce: the work reads state when it runs (latest value wins), not when it was requested", function()
    local w = Boot()
    local seen
    local value = 1
    w.DL.Debounce("v", function() seen = value end)
    value = 2
    w.DL.Debounce("v", function() seen = -1 end) -- ignored: first function is kept
    value = 3
    w:advance(150)
    eq(seen, 3)
end)

test("debounce: quest event burst -> one rebuild/record after 150 ms; achievement events only while the finder is showing", function()
    local w = Boot({ characters = { { name = "Tester", id = "100" } } })
    w:addQuest({ name = "Pledge: Volenfell", kind = "pledge" })
    local base = w.stats.timersScheduled or 0
    for _ = 1, 30 do w:fire(w.store.EVENT_QUEST_ADVANCED) end
    eq((w.stats.timersScheduled or 0) - base, 1)
    w:advance(150)
    ok(w.DL.settings.characterQuests["100"])
    -- finder hidden: achievement events do nothing
    w.state.finderShowing = false
    local scheduled = w.stats.timersScheduled or 0
    w:fire(w.store.EVENT_ACHIEVEMENT_UPDATED); w:fire(w.store.EVENT_ACHIEVEMENTS_UPDATED)
    eq(w.stats.timersScheduled or 0, scheduled)
    w.state.finderShowing = true
    for _ = 1, 10 do w:fire(w.store.EVENT_ACHIEVEMENT_UPDATED) end
    eq((w.stats.timersScheduled or 0) - scheduled, 1)
end)

test("debounce: typing in the search box rebuilds once with the final text; unchanged text schedules nothing", function()
    local w = Boot()
    w:refresh()
    local box = w.controlsByName["DungeoneersLedgerSearchBox"]
    ok(box, "search box not created")
    local views = w.stats.refreshViews
    for _, text in ipairs({ "f", "fu", "fun", "fung", "Fungal" }) do
        box:SetText(text); box:Fire("OnTextChanged"); w:advance(20)
    end
    eq(w.stats.refreshViews, views, "no rebuild while typing within 150 ms")
    w:advance(200)
    eq(w.stats.refreshViews, views + 1)
    eq(w.DL.GetSearchText(), "fungal")
    for _, h in ipairs(w:snapshot()) do eq(#Data.flatten(h), 2) end
    local timers = w.stats.timersScheduled
    box:Fire("OnTextChanged") -- same text again
    eq(w.stats.timersScheduled, timers)
    box:SetText("  FUNGAL!! "); box:Fire("OnTextChanged")
    eq(w.stats.timersScheduled, timers, "normalised text is unchanged")
    box:SetText(""); box:Fire("OnTextChanged"); w:advance(150)
    for _, h in ipairs(w:snapshot()) do eq(#Data.flatten(h), #w.dungeons) end
end)

test("debounce: completing an achievement updates rows and summary after the debounce (no full rebuild unless needed)", function()
    local w = Boot()
    w:refresh()
    local d = Data.dungeonByName(w, "Volenfell")
    local views = w.stats.refreshViews
    local summary = w.controlsByName["DungeoneersLedgerSummary"]
    w.finder:RefreshButtons()
    local before = summary:GetText()
    w:setAchievementState(d.normalAch, true)
    w:fire(w.store.EVENT_ACHIEVEMENT_UPDATED)
    eq(summary:GetText(), before, "nothing before the debounce")
    w:advance(150)
    ok(summary:GetText() ~= before, "summary should change: " .. summary:GetText())
    eq(w.stats.refreshViews, views, "no list rebuild with default settings")
    w.DL.settings.hideCompleted = true
    w:setAchievementState(d.vetAch, true)
    w:fire(w.store.EVENT_ACHIEVEMENT_UPDATED); w:advance(150)
    eq(w.stats.refreshViews, views + 1, "hide-completed needs a rebuild")
end)
