-- D&D Sorcerer spell macro + GUI editor. Private-server use.

local M = {}

local CONFIG_PATH = hs.configdir .. "/dnd_spells.json"
local UI_PATH     = hs.configdir .. "/dnd_spells_ui.html"

local MOUSE_BTN = {
  mouse3=2, mouse4=3, mouse5=4, mouse6=5, mouse7=6,
  mouse8=7, mouse9=8, mouse10=9, mouse11=10, mouse12=11,
}
local MOUSE_BTN_REV = {}
for k, v in pairs(MOUSE_BTN) do MOUSE_BTN_REV[v] = k end

local CURRENT_VERSION = 2
local DEFAULT_CONFIG = {
  version = CURRENT_VERSION,
  geometry = {
    slots = { -90, -18, 54, 126, -162 },   -- pentagon, point up
    flick_radius = 220,
  },
  tuning = {
    radius_jitter=25, angle_jitter=8,
    hold_ms=55, hold_ms_jitter=10, hold_jitter_ms=12,
    pre_ms=60,  pre_jitter_ms=15,             -- give the wheel time to fully open
    post_ms=8,  post_jitter_ms=3,
    steps=5, steps_jitter=1,
    step_jitter_px=4, step_delay_jitter_ms=3,
    curve_offset=18,
    restore_cursor=false,                     -- snap mouse back to origin?  set true
                                              -- only for cursor-mode games; in mouse-
                                              -- look (D&D, FPS), snap-back = camera spin
  },
  bindings = {
    { kind="key", ident="f1",  wheel="q", slot=1, mods={} },
    { kind="key", ident="f2",  wheel="q", slot=2, mods={} },
    { kind="key", ident="f3",  wheel="q", slot=3, mods={} },
    { kind="key", ident="f4",  wheel="q", slot=4, mods={} },
    { kind="key", ident="f5",  wheel="q", slot=5, mods={} },
    { kind="key", ident="f6",  wheel="e", slot=1, mods={} },
    { kind="key", ident="f7",  wheel="e", slot=2, mods={} },
    { kind="key", ident="f8",  wheel="e", slot=3, mods={} },
    { kind="key", ident="f9",  wheel="e", slot=4, mods={} },
    { kind="key", ident="f10", wheel="e", slot=5, mods={} },
  },
}

local config

local function fillDefaults(cfg)
  cfg.tuning = cfg.tuning or {}
  for k, v in pairs(DEFAULT_CONFIG.tuning) do
    if cfg.tuning[k] == nil then cfg.tuning[k] = v end
  end
  cfg.geometry = cfg.geometry or {}
  for k, v in pairs(DEFAULT_CONFIG.geometry) do
    if cfg.geometry[k] == nil then cfg.geometry[k] = v end
  end
  cfg.bindings = cfg.bindings or DEFAULT_CONFIG.bindings
end

local function migrateConfig(cfg)
  local v = cfg.version or 1
  if v < 2 then
    -- v2: drop snap-back (caused camera spin in mouse-look games),
    -- bump pre_ms so the in-game wheel is open before we start moving.
    cfg.tuning = cfg.tuning or {}
    cfg.tuning.pre_ms = 60
    cfg.tuning.pre_jitter_ms = 15
    cfg.tuning.restore_cursor = false
  end
  cfg.version = CURRENT_VERSION
end

local function loadConfig()
  local f = io.open(CONFIG_PATH, "r")
  if not f then config = DEFAULT_CONFIG; M.saveConfig(); return end
  local raw = f:read("*all"); f:close()
  local ok, parsed = pcall(hs.json.decode, raw)
  if ok and parsed then config = parsed
  else hs.alert.show("D&D spells: bad JSON, using defaults"); config = DEFAULT_CONFIG end
  fillDefaults(config)
  migrateConfig(config)
  M.saveConfig()   -- persist any newly-filled defaults so the JSON stays current
end

function M.saveConfig()
  local f = io.open(CONFIG_PATH, "w")
  if not f then hs.alert.show("D&D spells: cannot write config"); return end
  f:write(hs.json.encode(config, true)); f:close()
end

math.randomseed(os.time() * 1000 + hs.timer.absoluteTime() % 1000)
local function jitter(b, a) return b + (math.random()*2 - 1) * a end

local function bezier(p0, p1, p2, t)
  local u = 1 - t
  return { x = u*u*p0.x + 2*u*t*p1.x + t*t*p2.x,
           y = u*u*p0.y + 2*u*t*p1.y + t*t*p2.y }
end

-- Tap that consumes all physical mouse movement.  Created lazily, kept around,
-- start()/stop()'d per cast so the user's hand can't fight the macro.
local mouseLockTap
local function ensureMouseLockTap()
  if mouseLockTap then return end
  mouseLockTap = hs.eventtap.new({
    hs.eventtap.event.types.mouseMoved,
    hs.eventtap.event.types.leftMouseDragged,
    hs.eventtap.event.types.rightMouseDragged,
    hs.eventtap.event.types.otherMouseDragged,
  }, function() return true end)
end

-- Single-flight macro tracker. Releasing the bound key cancels the in-flight
-- cast immediately: scheduled steps short-circuit, wheel key releases, mouse
-- lock stops, cursor snaps back to where you were aiming.
local activeMacro

local function tearDown(macro)
  if not macro or macro.done then return end
  macro.done = true
  hs.eventtap.event.newKeyEvent({}, macro.wheel, false):post()
  if mouseLockTap then mouseLockTap:stop() end
  if macro.origin and config and config.tuning and config.tuning.restore_cursor then
    hs.mouse.absolutePosition(macro.origin)
  end
  if activeMacro == macro then activeMacro = nil end
end

local function cancelActiveMacro()
  if activeMacro and not activeMacro.done then
    activeMacro.cancelled = true
    tearDown(activeMacro)
  end
end

local function loadSpell(wheel, slot, onDone)
  -- A new cast cancels any in-flight one
  if activeMacro and not activeMacro.done then
    activeMacro.cancelled = true
    tearDown(activeMacro)
  end

  local g, t = config.geometry, config.tuning
  local base = g.slots[slot]; if not base then return end
  local angle   = math.rad(jitter(base, t.angle_jitter))
  local radius  = jitter(g.flick_radius, t.radius_jitter)
  local holdMs  = math.max(10, jitter(t.hold_ms, t.hold_ms_jitter or 0))
  local steps   = math.max(2, math.floor(jitter(t.steps, t.steps_jitter or 0) + 0.5))
  local postMs  = math.max(0, jitter(t.post_ms or 8, t.post_jitter_ms or 0))
  local preMs   = math.max(0, jitter(t.pre_ms, t.pre_jitter_ms))
  local settleMs= math.max(0, jitter(holdMs*0.3, t.hold_jitter_ms))
  local origin  = hs.mouse.absolutePosition()
  local sc      = hs.mouse.getCurrentScreen():fullFrame()
  local center  = { x = sc.x + sc.w/2, y = sc.y + sc.h/2 }
  local target  = { x = center.x + radius*math.cos(angle),
                    y = center.y + radius*math.sin(angle) }

  -- Precompute Bezier waypoints
  local waypoints = {}
  local dx, dy = target.x - center.x, target.y - center.y
  local len = math.sqrt(dx*dx + dy*dy)
  if len == 0 then
    waypoints[1] = target
  else
    local nx, ny = -dy/len, dx/len
    local bow = jitter(0, t.curve_offset)
    local mid = { x = (center.x+target.x)/2 + nx*bow,
                  y = (center.y+target.y)/2 + ny*bow }
    for i = 1, steps do
      local tt = i / steps
      local p = bezier(center, mid, target, tt)
      p.x = p.x + jitter(0, t.step_jitter_px)
      p.y = p.y + jitter(0, t.step_jitter_px)
      waypoints[i] = p
    end
  end
  local baseStepDelay = holdMs / #waypoints
  local sdJitter = t.step_delay_jitter_ms or 0

  local macro = { cancelled = false, done = false, wheel = wheel, origin = origin }
  activeMacro = macro

  ensureMouseLockTap()
  mouseLockTap:start()
  hs.eventtap.event.newKeyEvent({}, wheel, true):post()

  local function step(i)
    if macro.cancelled or macro.done then return end
    if i > #waypoints then
      hs.timer.doAfter(settleMs / 1000, function()
        if macro.cancelled or macro.done then return end
        hs.eventtap.event.newKeyEvent({}, wheel, false):post()
        hs.timer.doAfter(postMs / 1000, function()
          if macro.cancelled or macro.done then return end
          macro.done = true
          if mouseLockTap then mouseLockTap:stop() end
          if t.restore_cursor then hs.mouse.absolutePosition(origin) end
          if activeMacro == macro then activeMacro = nil end
          if onDone then onDone() end
        end)
      end)
      return
    end
    hs.mouse.absolutePosition(waypoints[i])
    local sd = math.max(0, baseStepDelay + jitter(0, sdJitter))
    hs.timer.doAfter(sd / 1000, function() step(i+1) end)
  end

  hs.timer.doAfter(preMs / 1000, function()
    if macro.cancelled or macro.done then return end
    step(1)
  end)
end

-- Sequence runner: lets a single button fire multiple (wheel, slot) casts
-- back-to-back.  Cancellation from the released callback aborts the whole
-- sequence at the next safe point.  Each action's `delay_ms` is honored
-- before that action fires (so row 2's delay is the gap between cast 1 and
-- cast 2).  Row 1's delay also works -- use it as a hold-then-fire delay.
local activeSequence
local function loadSpellSequence(actions)
  if activeSequence then activeSequence.cancelled = true end
  local seq = { cancelled = false }
  activeSequence = seq
  local function runNext(i)
    if seq.cancelled then return end
    if i > #actions then
      if activeSequence == seq then activeSequence = nil end
      return
    end
    local a = actions[i]
    local delay = math.max(0, tonumber(a.delay_ms) or 0)
    local function fire()
      if seq.cancelled then return end
      loadSpell(a.wheel, a.slot, function() runNext(i+1) end)
    end
    if delay > 0 then hs.timer.doAfter(delay / 1000, fire) else fire() end
  end
  runNext(1)
end

local function cancelActiveSequence()
  if activeSequence then activeSequence.cancelled = true end
  cancelActiveMacro()
end

local registeredHotkeys = {}
local mouseHandlers = {}
local mouseTap

local function modsMatch(flags, req)
  local want = {cmd=false,shift=false,alt=false,ctrl=false,fn=false}
  for _, m in ipairs(req or {}) do want[m] = true end
  for k, v in pairs(want) do
    if (flags[k] or false) ~= v then return false end
  end
  return true
end

local function unbindAll()
  for _, hk in ipairs(registeredHotkeys) do hk:delete() end
  registeredHotkeys = {}; mouseHandlers = {}
  if mouseTap then mouseTap:stop(); mouseTap = nil end
end

local function bindAll()
  unbindAll()

  -- Group bindings by (kind, ident, mods). Multiple rows on the same button
  -- merge into one group whose actions all fire (sequentially) on press.
  local function modKey(mods)
    local copy = {}
    for i, m in ipairs(mods or {}) do copy[i] = m end
    table.sort(copy)
    return table.concat(copy, "+")
  end
  local groups, order = {}, {}
  for _, b in ipairs(config.bindings or {}) do
    if b.ident and b.ident ~= "" and b.wheel and b.slot then
      local key = b.kind .. "|" .. b.ident .. "|" .. modKey(b.mods)
      if not groups[key] then
        groups[key] = { kind = b.kind, ident = b.ident, mods = b.mods or {}, actions = {} }
        table.insert(order, key)
      end
      table.insert(groups[key].actions, {
        wheel = b.wheel, slot = b.slot,
        delay_ms = tonumber(b.delay_ms) or 0,
      })
    end
  end

  local mouseUsed = false
  for _, key in ipairs(order) do
    local g = groups[key]
    local actions = g.actions
    if g.kind == "key" then
      local ok, hk = pcall(hs.hotkey.bind, g.mods, g.ident,
        function() loadSpellSequence(actions) end,   -- pressed
        function() cancelActiveSequence() end        -- released
      )
      if ok then table.insert(registeredHotkeys, hk) end
    elseif g.kind == "mouse" then
      local btn = MOUSE_BTN[g.ident]
      if btn then
        mouseHandlers[btn] = mouseHandlers[btn] or {}
        table.insert(mouseHandlers[btn], {
          mods = g.mods,
          action = function() loadSpellSequence(actions) end,
        })
        mouseUsed = true
      end
    end
  end

  if mouseUsed then
    mouseTap = hs.eventtap.new(
      { hs.eventtap.event.types.otherMouseDown,
        hs.eventtap.event.types.otherMouseUp },
      function(e)
        local btn = e:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
        local handlers = mouseHandlers[btn]
        if not handlers then return false end
        if e:getType() == hs.eventtap.event.types.otherMouseUp then
          -- Any release of a bound mouse button cancels the in-flight cast
          hs.timer.doAfter(0, cancelActiveSequence)
          return true
        end
        local flags = e:getFlags()
        for _, h in ipairs(handlers) do
          if modsMatch(flags, h.mods) then
            hs.timer.doAfter(0, h.action)
            return true
          end
        end
        return false
      end
    )
    mouseTap:start()
  end
  print("D&D spells: " .. #(config.bindings or {}) .. " bindings, " .. #order .. " unique trigger(s)")
end

local captureTap
local function flagsToMods(flags)
  local out = {}
  for _, n in ipairs({"cmd","shift","alt","ctrl","fn"}) do
    if flags[n] then table.insert(out, n) end
  end
  return out
end

local function startCapture(cb)
  if captureTap then captureTap:stop() end
  captureTap = hs.eventtap.new(
    { hs.eventtap.event.types.keyDown,
      hs.eventtap.event.types.otherMouseDown },
    function(e)
      local typ = e:getType()
      local mods = flagsToMods(e:getFlags())
      if typ == hs.eventtap.event.types.keyDown then
        local key = hs.keycodes.map[e:getKeyCode()]
        captureTap:stop(); captureTap = nil
        if key == "escape" then cb(nil)
        else cb({ kind="key", ident=key, mods=mods }) end
      else
        local btn = e:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
        local name = MOUSE_BTN_REV[btn]
        if name then
          captureTap:stop(); captureTap = nil
          cb({ kind="mouse", ident=name, mods=mods })
        end
      end
      return true
    end
  )
  captureTap:start()
end

local webview, ucc

local function showUI()
  if webview then webview:delete(); webview = nil end
  ucc = hs.webview.usercontent.new("dndspells")
  ucc:setCallback(function(msg)
    local body = msg.body
    if type(body) == "string" then body = hs.json.decode(body) or {} end
    if body.type == "load" then
      webview:evaluateJavaScript("setConfig(" .. hs.json.encode(config) .. ")")
    elseif body.type == "save" then
      config = body.config; M.saveConfig(); bindAll()
    elseif body.type == "capture" then
      startCapture(function(result)
        local payload = hs.json.encode({ rowIndex = body.rowIndex, result = result })
        webview:evaluateJavaScript("captureDone(" .. payload .. ")")
      end)
    end
  end)
  local rect = hs.geometry.rect(0, 0, 780, 640)
  rect.center = hs.screen.mainScreen():frame().center
  webview = hs.webview.new(rect, {developerExtrasEnabled=true}, ucc)
    :windowStyle({"titled","closable","resizable"})
    :windowTitle("D&D Spell Bindings")
    :allowTextEntry(true)
    :url("file://" .. UI_PATH)
    :show()
  webview:bringToFront()
end

local menubar
function M.start()
  pcall(hs.allowAppleScript, true)   -- enable osascript reloads from the installer
  loadConfig(); bindAll()
  menubar = hs.menubar.new()
  menubar:setTitle("🪄")
  menubar:setMenu(function() return {
    { title = "Settings…", fn = showUI },
    { title = "-" },
    { title = "Reload Config", fn = function() loadConfig(); bindAll(); hs.alert.show("Reloaded") end },
    { title = "Reveal Config in Finder", fn = function() hs.execute("open -R '" .. CONFIG_PATH .. "'") end },
    { title = "-" },
    { title = "Config: " .. CONFIG_PATH, disabled = true },
  } end)
end

return M
