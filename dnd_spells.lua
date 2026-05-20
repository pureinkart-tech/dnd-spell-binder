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

local DEFAULT_CONFIG = {
  version = 1,
  geometry = {
    slots = { -90, -18, 54, 126, -162 },   -- pentagon, point up
    flick_radius = 220,
  },
  tuning = {
    radius_jitter=25, angle_jitter=8,
    hold_ms=55, hold_jitter_ms=12,
    pre_ms=15,  pre_jitter_ms=6,
    steps=5, step_jitter_px=4, curve_offset=18,
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

local function loadConfig()
  local f = io.open(CONFIG_PATH, "r")
  if not f then config = DEFAULT_CONFIG; M.saveConfig(); return end
  local raw = f:read("*all"); f:close()
  local ok, parsed = pcall(hs.json.decode, raw)
  if ok and parsed then config = parsed
  else hs.alert.show("D&D spells: bad JSON, using defaults"); config = DEFAULT_CONFIG end
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

local function moveAlongCurve(from, to, steps, holdMs, stepJ, curveOff)
  local dx, dy = to.x - from.x, to.y - from.y
  local len = math.sqrt(dx*dx + dy*dy); if len == 0 then return end
  local nx, ny = -dy/len, dx/len
  local bow = jitter(0, curveOff)
  local mid = { x = (from.x+to.x)/2 + nx*bow, y = (from.y+to.y)/2 + ny*bow }
  local stepDelay = math.floor((holdMs * 1000) / steps)
  for i = 1, steps do
    local t = i / steps
    local p = bezier(from, mid, to, t)
    p.x = p.x + jitter(0, stepJ); p.y = p.y + jitter(0, stepJ)
    hs.mouse.absolutePosition(p)
    hs.timer.usleep(stepDelay)
  end
end

local function loadSpell(wheel, slot)
  local g, t = config.geometry, config.tuning
  local base = g.slots[slot]; if not base then return end
  local angle  = math.rad(jitter(base, t.angle_jitter))
  local radius = jitter(g.flick_radius, t.radius_jitter)
  local origin = hs.mouse.absolutePosition()
  local sc = hs.mouse.getCurrentScreen():fullFrame()
  local center = { x = sc.x + sc.w/2, y = sc.y + sc.h/2 }
  local target = { x = center.x + radius*math.cos(angle),
                   y = center.y + radius*math.sin(angle) }
  hs.eventtap.event.newKeyEvent({}, wheel, true):post()
  hs.timer.usleep(math.floor(jitter(t.pre_ms, t.pre_jitter_ms) * 1000))
  moveAlongCurve(center, target, t.steps, t.hold_ms, t.step_jitter_px, t.curve_offset)
  hs.timer.usleep(math.floor(jitter(t.hold_ms*0.3, t.hold_jitter_ms) * 1000))
  hs.eventtap.event.newKeyEvent({}, wheel, false):post()
  hs.timer.usleep(8000)
  hs.mouse.absolutePosition(origin)
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
  local mouseUsed = false
  for _, b in ipairs(config.bindings or {}) do
    if b.ident and b.ident ~= "" then
      if b.kind == "key" then
        local ok, hk = pcall(hs.hotkey.bind, b.mods or {}, b.ident,
          function() loadSpell(b.wheel, b.slot) end)
        if ok then table.insert(registeredHotkeys, hk) end
      elseif b.kind == "mouse" then
        local btn = MOUSE_BTN[b.ident]
        if btn then
          mouseHandlers[btn] = mouseHandlers[btn] or {}
          table.insert(mouseHandlers[btn], {
            mods = b.mods or {},
            action = function() loadSpell(b.wheel, b.slot) end,
          })
          mouseUsed = true
        end
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
        local flags = e:getFlags()
        for _, h in ipairs(handlers) do
          if modsMatch(flags, h.mods) then
            if e:getType() == hs.eventtap.event.types.otherMouseDown then
              hs.timer.doAfter(0, h.action)
            end
            return true
          end
        end
        return false
      end
    )
    mouseTap:start()
  end
  print("D&D spells: " .. #(config.bindings or {}) .. " bindings active")
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
