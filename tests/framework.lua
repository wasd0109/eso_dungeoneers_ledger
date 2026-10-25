-- Minimal test framework. Tests: test("name", function() ... end). Names starting with test_BUG_ document a
-- real addon bug/risk: they are reported separately and do not make the run "fail" (exit code 2 instead of 1).
T = { tests = {}, current = nil }

function test(name, fn)
    T.tests[#T.tests + 1] = { name = name, fn = fn }
end

local SKIP = {}
function skip(reason) error({ skip = SKIP, reason = reason }, 0) end

local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
end

function ok(cond, msg)
    if not cond then error(msg or "assertion failed", 2) end
end

function fails(fn, msg)
    local good = pcall(fn)
    if good then error(msg or "expected an error", 2) end
end

function deepeq(a, b, path)
    path = path or "value"
    if type(a) ~= type(b) then return false, path .. ": type " .. type(a) .. " vs " .. type(b) end
    if type(a) ~= "table" then
        if a ~= b then return false, path .. ": " .. show(a) .. " vs " .. show(b) end
        return true
    end
    for k, v in pairs(a) do
        local good, why = deepeq(v, b[k], path .. "." .. tostring(k))
        if not good then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing" end
    end
    return true
end

function same(a, b, msg)
    local good, why = deepeq(a, b)
    if not good then error((msg and (msg .. ": ") or "") .. why, 2) end
end

function T.run(filter)
    local passed, failed, bugs, skipped, bugPass = 0, 0, 0, 0, 0
    local failures, bugList, skips = {}, {}, {}
    for _, t in ipairs(T.tests) do
        if not filter or t.name:find(filter, 1, true) then
            T.current = t
            local good, err = xpcall(t.fn, function(e)
                if type(e) == "table" then return e end
                return tostring(e) .. "\n" .. debug.traceback("", 2)
            end)
            local isBug = t.name:find("^test_BUG_") ~= nil
            if good then
                if isBug then bugPass = bugPass + 1 end
                passed = passed + 1
                io.write(".")
            elseif type(err) == "table" and err.skip == SKIP then
                skipped = skipped + 1
                skips[#skips + 1] = t.name .. ": " .. err.reason
                io.write("s")
            elseif isBug then
                bugs = bugs + 1
                bugList[#bugList + 1] = { t.name, err }
                io.write("B")
            else
                failed = failed + 1
                failures[#failures + 1] = { t.name, err }
                io.write("F")
            end
        end
    end
    io.write("\n\n")
    local function indent(e) return (tostring(e):gsub("\n", "\n  ")) end
    for _, f in ipairs(failures) do print("FAIL " .. f[1] .. "\n  " .. indent(f[2])) end
    for _, f in ipairs(bugList) do print("KNOWN BUG " .. f[1] .. "\n  " .. indent(f[2])) end
    local seen = {}
    for _, s in ipairs(skips) do
        local reason = s:match(": (.*)$")
        if not seen[reason] then seen[reason] = 0 end
        seen[reason] = seen[reason] + 1
    end
    for reason, n in pairs(seen) do print("SKIPPED (" .. n .. " tests): " .. reason) end
    print(string.format("\nLua runtime: %s | total %d | passed %d | failed %d | known-bug tests failing %d | skipped %d",
        RUNNER_VERSION, passed + failed + bugs + skipped, passed, failed, bugs, skipped))
    if bugPass > 0 then print(bugPass .. " test_BUG_ tests now PASS (bug fixed? rename them)") end
    if failed > 0 then return 1 end
    if bugs > 0 then return 2 end
    return 0
end
