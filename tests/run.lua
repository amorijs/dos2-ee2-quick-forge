-- Test runner for QuickForge's pure-logic core.
-- Usage (from repo root): lua tests/run.lua

local runner = {
    passed = 0,
    failed = 0,
    failures = {},
}

local currentTest = nil

function runner.test(name, fn)
    currentTest = name
    local ok, err = pcall(fn)
    if ok then
        runner.passed = runner.passed + 1
    else
        runner.failed = runner.failed + 1
        table.insert(runner.failures, ("%s: %s"):format(name, tostring(err)))
    end
    currentTest = nil
end

function runner.assertEquals(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
    end
end

---Compares two flat arrays element-wise.
function runner.assertListEquals(actual, expected, label)
    label = label or "list"
    if #actual ~= #expected then
        error(("%s: expected %d elements {%s}, got %d {%s}"):format(
            label, #expected, table.concat(expected, ", "), #actual, table.concat(actual, ", ")), 2)
    end
    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            error(("%s[%d]: expected %s, got %s"):format(label, i, tostring(expected[i]), tostring(actual[i])), 2)
        end
    end
end

function runner.assertContains(list, value, label)
    for _, v in ipairs(list) do
        if v == value then return end
    end
    error(("%s: expected to contain %s"):format(label or "list", tostring(value)), 2)
end

function runner.assertNotContains(list, value, label)
    for _, v in ipairs(list) do
        if v == value then
            error(("%s: expected NOT to contain %s"):format(label or "list", tostring(value)), 2)
        end
    end
end

local scriptDir = arg[0]:match("^(.*)[/\\][^/\\]+$") or "."
runner.Core = dofile(scriptDir
    .. "/../Mods/QuickForge_1993d511-b789-4edc-9e0a-cf15ea5ffd80/Story/RawFiles/Lua/QuickForge/Core.lua")

dofile(scriptDir .. "/test_core.lua")(runner)

print(("Tests: %d passed, %d failed"):format(runner.passed, runner.failed))
for _, failure in ipairs(runner.failures) do
    print("FAIL  " .. failure)
end
os.exit(runner.failed == 0 and 0 or 1)
