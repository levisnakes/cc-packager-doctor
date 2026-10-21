-- Packager Doctor: checks why a Create packager won't take packages into its vault.
-- Run it, read the report, press R to check again or Q to quit.
-- Leave a stuck package in any chest on the network and it gets checked too.

PACKAGER = nil   -- network name, e.g. "Create_Packager_3" (nil = find it)
VAULT = nil      -- network name, e.g. "create:item_vault_5" (nil = find it)

-- ==== program ====
local VERSION = "1.0.0"

local function names()
  local seen, out = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if not seen[n] then seen[n] = true out[#out + 1] = n end
  end
  return out
end

local function isPackager(n)
  return peripheral.hasType(n, "Create_Packager") or peripheral.hasType(n, "Create_Repackager")
end

local function isVault(n)
  return peripheral.hasType(n, "create:item_vault") or n:find("item_vault", 1, true) ~= nil
end

local function pick(setting, test, what)
  if setting then
    if peripheral.isPresent(setting) then return setting end
    return nil, what .. " '" .. setting .. "' not found"
  end
  local found = {}
  for _, n in ipairs(names()) do if test(n) then found[#found + 1] = n end end
  if #found == 0 then return nil, "no " .. what .. " found (wired modem on it and turned on?)" end
  if #found > 1 then
    return nil, "found " .. #found .. " " .. what .. "s: " .. table.concat(found, ", ") ..
      "\nset " .. what:upper() .. " at the top of this file"
  end
  return found[1]
end

local function short(id) return (id:gsub("^minecraft:", "")) end
local function key(it) return it.name .. "|" .. (it.nbt or "") end

local lines = {}
local function say(color, text)
  lines[#lines + 1] = { color, text }
end
local problems = 0
local function bad(text) problems = problems + 1 say(colors.red, "X " .. text) end
local function good(text) say(colors.lime, "+ " .. text) end
local function info(text) say(colors.lightGray, "  " .. text) end
local function tip(text) say(colors.yellow, "  > " .. text) end

-- How much of each package item fits, the same way Create unpacks:
-- all of it must fit or nothing goes in.
local function simulate(pkg, vaultItems, size, slotLimit)
  local partialRoom, emptySlots = {}, size
  for _ in pairs(vaultItems) do emptySlots = emptySlots - 1 end
  local items = pkg.list() or {}
  local missing = {}
  local stacks = {}
  for slot, it in pairs(items) do
    local d = pkg.getItemDetail(slot) or it
    stacks[#stacks + 1] = { key = key(it), name = it.name, count = it.count,
      max = math.min(d.maxCount or 64, slotLimit) }
  end
  -- room in partial stacks of the same item
  for _, s in ipairs(stacks) do
    if partialRoom[s.key] == nil then
      local room = 0
      for _, v in pairs(vaultItems) do
        if key(v) == s.key then room = room + math.max(0, s.max - v.count) end
      end
      partialRoom[s.key] = room
    end
  end
  local fits = true
  for _, s in ipairs(stacks) do
    local left = s.count
    local use = math.min(left, partialRoom[s.key])
    partialRoom[s.key] = partialRoom[s.key] - use
    left = left - use
    while left > 0 and emptySlots > 0 do
      emptySlots = emptySlots - 1
      left = left - math.min(left, s.max)
    end
    if left > 0 then
      fits = false
      missing[#missing + 1] = left .. "x " .. short(s.name)
    end
  end
  return fits, #stacks, missing
end

local function packageName(pkg)
  local ok, addr = pcall(pkg.getAddress)
  if ok and addr and addr ~= "" then return "package to '" .. addr .. "'" end
  return "package (no address)"
end

local function checkPackage(label, pkg, vaultItems, size, slotLimit)
  local ok, fits, nStacks, missing = pcall(simulate, pkg, vaultItems, size, slotLimit)
  if not ok then
    info(label .. ": couldn't read contents (" .. tostring(fits) .. ")")
    return
  end
  if fits then
    good(label .. " (" .. packageName(pkg) .. ", " .. nStacks .. " stacks) would fit")
  else
    bad(label .. " (" .. packageName(pkg) .. ") does NOT fit")
    info("left over: " .. table.concat(missing, ", "))
    tip("the whole package must fit or the packager rejects it")
  end
end

local function run()
  lines, problems = {}, 0
  local pName, pErr = pick(PACKAGER, isPackager, "packager")
  local vName, vErr = pick(VAULT, isVault, "vault")
  if not pName then bad(pErr) end
  if not vName then bad(vErr) end
  if not pName or not vName then return end
  local packager, vault = peripheral.wrap(pName), peripheral.wrap(vName)
  info("packager: " .. pName)
  info("vault:    " .. vName)

  -- 1. vault space
  local size = vault.size()
  local vaultItems = vault.list()
  local used, types, total = 0, {}, 0
  for _, it in pairs(vaultItems) do
    used = used + 1
    types[key(it)] = true
    total = total + it.count
  end
  local nTypes = 0
  for _ in pairs(types) do nTypes = nTypes + 1 end
  local okLimit, slotLimit = pcall(vault.getItemLimit, 1)
  if not okLimit or not slotLimit then slotLimit = 64 end
  local free = size - used
  if free == 0 then
    bad("vault is FULL: " .. used .. "/" .. size .. " slots used")
    tip("every slot holds one item type; make the vault bigger or empty it")
  elseif free < 10 then
    bad("vault almost full: " .. free .. " of " .. size .. " slots free")
    tip("a package with more stacks than that gets rejected")
  else
    good("vault has room: " .. free .. " of " .. size .. " slots free")
  end
  info(total .. " items, " .. nTypes .. " item types")

  -- 2. is the packager actually attached to this vault?
  local okList, pItems = pcall(packager.list)
  if not okList or pItems == nil then
    bad("packager can't see any inventory")
    tip("the vault must touch the packager's BACK (opposite the side packages come out)")
  else
    local pTotal, pSlots = 0, 0
    for _, it in pairs(pItems) do pTotal = pTotal + it.count pSlots = pSlots + 1 end
    if pTotal == total and pSlots == used then
      if total == 0 then
        info("packager and vault are both empty, can't tell if they're attached")
      else
        good("packager is attached to this vault")
      end
    else
      bad("packager is attached to a DIFFERENT inventory")
      info("packager sees " .. pTotal .. " items, vault has " .. total)
      tip("the vault must touch the packager's BACK (opposite the side packages come out)")
    end
  end

  -- 3. is it busy?
  local okPkg, held = pcall(packager.getPackage)
  if okPkg and held then
    bad("packager is holding a package and won't accept another")
    tip("it can't push it out: check what's in front of it (belt, funnel, frogport)")
    checkPackage("held package", held, vaultItems, size, slotLimit)
  else
    good("packager isn't holding a package")
  end

  -- 4. any stuck packages lying around on the network
  local found = 0
  for _, n in ipairs(names()) do
    if n ~= pName and n ~= vName then
      local inv = peripheral.wrap(n)
      if inv and inv.list and inv.getItemDetail then
        local okL, items = pcall(inv.list)
        if okL and items then
          for slot, it in pairs(items) do
            if it.name:find("package", 1, true) then
              local okD, d = pcall(inv.getItemDetail, slot)
              if okD and d and d.package then
                found = found + 1
                -- keep the report on one screen
                if found <= 4 then checkPackage(n .. " slot " .. slot, d.package, vaultItems, size, slotLimit) end
              end
            end
          end
        end
      end
    end
  end
  if found > 4 then info("(" .. (found - 4) .. " more packages not shown)") end
  if found == 0 then
    info("no packages found in other inventories on the network")
    info("(put a stuck one in a chest on the modem network to test it)")
  end

  if problems == 0 then
    say(colors.lime, "")
    say(colors.lime, "Nothing wrong found from here.")
    tip("packages sent by FROGPORT only arrive if their address matches the frogport")
    tip("feeding by funnel/belt? the funnel must face INTO the packager")
  end
end

local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  print("Packager Doctor v" .. VERSION)
  for _, l in ipairs(lines) do
    term.setTextColor(l[1])
    print(l[2])
  end
  term.setTextColor(colors.gray)
  write("[R] check again  [Q] quit")
  term.setTextColor(colors.white)
end

local function check()
  local ok, err = pcall(run)
  if not ok then bad("error: " .. tostring(err)) end
  draw()
end

check()
while true do
  local ev, a = os.pullEvent()
  if ev == "char" and (a == "r" or a == "R") then
    check()
  elseif ev == "char" and (a == "q" or a == "Q") then
    term.setCursorPos(1, select(2, term.getSize()))
    print()
    break
  elseif ev == "package_received" then
    -- Create fires this on the packager's computer after a successful unpack
    lines[#lines + 1] = { colors.lime, "+ a package just unpacked into the vault" }
    draw()
  elseif ev == "peripheral" or ev == "peripheral_detach" then
    check()
  end
end
