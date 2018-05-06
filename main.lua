#!/usr/bin/env lua

if #arg < 1 then
  print("Usage: " .. arg[0] .. " [--no-metadata] <file>")
  print("  prints the contents of a Cobre module")
  os.exit(0)
end

local file = io.open(arg[#arg], "rb")

local colors = {
  reset = "\x1b[0;39m",
  string = "\x1b[1;30m",
  error = "\x1b[1;41m",
  module = "\x1b[0;34m",
  type = "\x1b[0;36m",
  func = "\x1b[0;35m",
  reg = "\x1b[0;32m",
  inst = "\x1b[0;34m",
  gray = "\x1b[1;30m",
}

local lines = {}

local linebuf = {}
local bytebuf = {}

function pushbytes (color)
  bytebuf.color = color or bytebuf.color or colors.reset
  table.insert(linebuf, bytebuf)
  local buf = bytebuf
  bytebuf = {}
  return buf
end

local ascii = {"nul", "soh", "stx", "etx", "eot", "enq", "ack", "bel", "bs",
  "ht", "lf", "vt", "ff", "cr", "so", "si", "dle", "dc1", "dc2", "dc3", "dc4",
  "nak", "syn", "etb", "can", "em", "sub", "esc", "fs", "gs", "rs", "us", "sp"}

function pushstr ()
  for i = 1, #bytebuf do
    local b, ch = bytebuf[i]
    if b <= 32 then ch = ascii[b+1]
    elseif b == 127 then ch = "del"
    else ch = string.char(bytebuf[i]) end
    bytebuf[i] = ch
  end
  return pushbytes(colors.string)
end

function pushline (...)
  local line = {bytes=linebuf, info=table.pack(...), extra=""}
  table.insert(lines, line)
  linebuf = {}
  return line
end

function rbyte ()
  local s = file:read(1)
  if s == nil or s == "" then
    fail("Unexpected end of file")
  end
  local b = string.byte(s)
  table.insert(bytebuf, b)
  return b
end

function rint (color)
  local n = 0
  local byte = rbyte()
  while (byte & 0x80) > 0  do
    n = (n << 7) | (byte & 0x7f)
    byte = rbyte()
  end
  n = (n << 7) | (byte & 0x7f)
  return n, pushbytes(color)
end

function rstr ()
  local count, countbuf = rint()
  local str = file:read(count)
  for i = 1, count do
    local b = str:byte(i)
    table.insert(bytebuf, b)
  end
  local strbuf = pushstr()
  if #str ~= count then
    countbuf.color = colors.error
    fail("string too long")
  else return str, strbuf end
end

function string:padleft (size, char)
  char = char or " "
  local str = self
  while #str < size do
    str = char .. str
  end
  return str
end

function printall ()
  if #bytebuf > 0 then pushbytes() end
  if #linebuf > 0 then pushline() end

  local sep = colors.gray .. "  | " .. colors.reset

  local pos = 0
  for _, data in ipairs(lines) do
    if type(data) == "string" then
      print(data)
      goto endloop
    end

    function tos (v, sep)
      if type(v) == "function" then return v()
      elseif type(v) == "table" then
        for i, u in ipairs(v) do v[i] = tos(u) end
        return table.concat(v, v.sep or sep or " ")
      else return tostring(v) end
    end

    -- Call all functions and store their result
    local info = tos(data.info, "")

    local n = 0
    local line = ("%4x"):format(pos) .. ":"
    for _, group in ipairs(data.bytes) do
      line = line .. group.color
      for _, byte in ipairs(group) do
        n = n+1
        local str = tostring(byte):padleft(4)
        line = line .. str
        if n == 8 then
          line = line .. colors.gray .. "  | " .. colors.reset .. info
          info = data.extra
          print(line .. colors.reset)
          pos = pos+n
          line = ("%4x"):format(pos) .. ":" .. group.color
          n = 0
        end
      end
      line = line
    end
    pos = pos+n
    if line ~= "" then
      while n < 8 do
        line = line .. "    "
        n = n+1
      end
      line = line .. colors.gray .. "  | " .. colors.reset .. info
      print(line .. colors.reset)
    end
    ::endloop::
  end
end

function fail (msg)
  if #bytebuf > 0 then pushbytes() end
  if #linebuf > 0 then
    if msg then msg = colors.error .. msg end
    pushline(msg)
    msg = nil
  end
  printall()
  if msg then print(colors.error .. msg) end
  os.exit(0)
end

-------------------------------------------------------------------------------
---                             Module contents                             ---
-------------------------------------------------------------------------------

function readsig ()
  local sig = "Cobre 0.5"
  local match = ""

  function _fail ()
    pushbytes(colors.error)
    pushline("Signature: ", colors.string, match, colors.error, sig)
    fail()
  end

  while #sig > 0 do
    if rbyte() == sig:byte() then
      match = match .. sig:sub(1, 1)
      sig = sig:sub(2)
      pushstr()
    else return _fail() end
  end

  if rbyte() == 0 then
    pushbytes()
  else return _fail() end

  pushline("Signature: ", colors.string, match)
end

local modules = {}
local functions = {}
local types = {}

local tcount = {}
local fcount = {}

function modules.new (id, name)
  local mod = {id=id, name=name}
  modules[id] = mod
  return mod
end
function modules.get (id)
  return function ()
    local self = modules[id]
    if not self then return colors.error .. id .. colors.reset end
    return colors.module .. (self.name or self.id) .. colors.reset
  end
end

function types.new (id, name)
  if name then
    local c = tcount[name] or 0
    tcount[name] = c+1
  end
  local ty = {id=id, origname=name}
  types[id] = ty
  return ty
end
function types.get (id)
  return function ()
    local self = types[id]
    if not self then return colors.error .. id .. colors.reset end
    local name = self.name or self.origname
    if not name or tcount[name] > 1 then name = self.id end
    return colors.type .. name .. colors.reset
  end
end

function functions.get (id)
  return function ()
    local self = functions[id+1]
    if not self then
      return colors.error .. id .. colors.reset
    end
    return colors.func .. (self.name or id) .. colors.reset
  end
end
function functions.new ()
  local id = #functions-1
  local fn = {id=id}
  table.insert(functions, fn)
  return fn
end

function readmodules ()
  local count = rint()
  pushline(count .. " modules")
  for i = 1, count do
    local mod = modules.new(i-1)
    local k = rint()
    if k == 0 then
      local name = rstr()
      mod.name = name
      pushline(modules.get(i-1), ": import ", colors.string, name)
    elseif k == 1 then
      local itemcount = rint()
      pushline(modules.get(i-1), ": define ", itemcount, " items")
      for j = 1, itemcount do
        local k = rint()
        local type, color
        if k == 0 then
          type = "module"
          color = colors.module
        elseif k == 1 then
          type = "type"
          color = colors.type
        elseif k == 2 then
          type = "function"
          color = colors.func
        else
          fail("Unknown type: " .. k)
        end
        local ix = rint(color)
        local name = rstr()
        pushline("  " .. type .. " " .. color .. ix .. " " .. colors.string .. name)
      end
    else
      fail("unknown import kind " .. k)
    end
  end
end

function readtypes ()
  local count = rint()
  pushline(count .. " types")
  for i = 1, count do
    local tp = types.new(i-1)
    local indexstr ={types.get(i-1), ": ", sep=""}
    local k, kbuf = rint()
    if k == 0 then
      pushline(indexstr, "null type")
    else
      kbuf.color = colors.module
      local name = rstr()
      pushline(indexstr, modules.get(k-1), ".", colors.string, name)
    end
  end
end

function readfunctions ()
  local count = rint()
  pushline(count .. " functions")
  for i = 1, count do
    local fn = functions.new()
    local indexstr = {functions.get(i-1), ": ", sep=""}
    local k, kbuf = rint()
    if k == 0 then
      pushline(indexstr, "null")
    elseif k == 1 then
      pushline(indexstr, "code")
      fn.code = true
    else
      kbuf.color = colors.module
      pushline(indexstr, "import")
    end
    local ins, outs = {sep=", "}, {sep=", "}

    fn.ins = rint()
    for i = 1, fn.ins do
      table.insert( ins, types.get(rint(colors.type)) )
    end

    fn.outs = rint()
    for i = 1, fn.outs do
      table.insert( outs, types.get(rint(colors.type)) )
    end

    pushline("  (", ins, ") -> (", outs, ")")
    if k > 1 then
      local name = rstr()
      pushline("  ", modules.get(k-3), ".", colors.string, name)
    end
  end
end

function readconstants ()
  local count = rint()
  pushline(count .. " constants")
  for i = 1, count do
    local fn = functions.new()
    fn.ins = 0
    fn.outs = 1
    local id = functions.get(fn.id)
    local k, kbuf = rint()
    if k == 1 then
      local n = rint()
      pushline(id, ": int " .. n)
    elseif k == 2 then
      local str = rstr()
      pushline(id, ": bin " .. colors.string .. str)
    elseif k >= 16 then
      kbuf.color = colors.func
      local ix = k-16
      local argc = 0
      if ix < #functions then
        argc = functions[ix+1].ins
      end
      local args = {sep=", "}
      for i = 1, argc do
        table.insert(args, functions.get(rint(colors.func)))
      end
      pushline(id, ": ", functions.get(ix), "(", args, ")")
    else fail("unknown constant kind " .. k) end
  end
end

function readcode (index, fn)
  local regs = 0
  local count = rint()
  pushline(count .. " instructions for " .. colors.func .. index)
  for i = 1, count do
    local outs, line = 0
    local k, kbuf = rint()
    if k == 1 then
      line = "hlt"
    elseif k == 2 then
      line = "var"
    elseif k == 3 then
      local a = rint(colors.reg)
      line = "dup " .. colors.reg .. a
      outs = 1
    elseif k == 4 then
      local a = rint(colors.reg)
      local b = rint(colors.reg)
      line = "set " .. colors.reg .. a .. " " .. b
    elseif k == 5 then
      local j = rint(colors.inst)
      line = "jmp " .. colors.inst .. j
    elseif k == 6 then
      local j = rint(colors.inst)
      local a = rint(colors.reg)
      line = "jif " .. colors.inst .. j .. colors.reg .. " " .. a
    elseif k == 7 then
      local j = rint(colors.inst)
      local a = rint(colors.reg)
      line = "nif " .. colors.inst .. j .. colors.reg .. " " .. a
    elseif k == 0 then
      local argc = fn.outs
      local args = {}
      for i = 1, argc do
        local arg = rint(colors.func)
        table.insert(args, arg)
      end
      line = "return " .. colors.reg .. table.concat(args, " ")
    elseif k >= 16 then
      kbuf.color = colors.func
      local ix = k-16
      local argc = 0
      outs = 1
      if ix < #functions then
        argc = functions[ix+1].ins
        outs = functions[ix+1].outs
      end
      local args = {}
      for i = 1, argc do
        local arg = rint(colors.reg)
        table.insert(args, colors.reg .. arg .. colors.reset)
      end
      line = {functions.get(ix)(), "(", table.concat(args, ", "), ")", sep=""}
    else fail("unknown instruction " .. k) end
    local reg = ""
    if outs > 0 then
      local o = {}
      for i = 0, outs-1 do table.insert(o, regs + i) end
      reg = "[" .. colors.reg .. table.concat(o, " ") .. colors.reset .. "] "
      regs = regs + outs
    end
    pushline(colors.inst .. i .. colors.reset .. ": ", reg, line)
  end
end

function readallcode ()
  for i, fn in ipairs(functions) do
    if fn.code then readcode(i-1, fn) end
  end
end

function readmetadata (indent1, indent2)
  local n = rint()
  if (n & 1) == 1 then
    local int = n >> 1
    pushline(indent1 .. int)
  else
    local len = n >> 2
    if (n & 2) == 0 then
      pushline(indent1 .. len .. " items")
      if (len > 0) then
        for i = 1, len-1 do
          readmetadata(indent2 .. "├╸", indent2 .. "│ ")
        end
        readmetadata(indent2 .. "╰╸", indent2 .. "  ")
      end
    else
      local str = ""
      for i = 1, len do
        str = str .. string.char(rbyte())
      end
      pushstr()
      pushline(indent1 .. colors.string .. str).extra = indent2
    end
  end
end

function pushsep () table.insert(lines, colors.gray ..
" - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
.. colors.reset) end


readsig()
pushsep()
readmodules()
pushsep()
readtypes()
pushsep()
readfunctions()
pushsep()
readconstants()
pushsep()
readallcode()

if arg[1] ~= "--no-metadata" then
  pushsep()
  pushline("Metadata")
  readmetadata("", "")
end

printall()