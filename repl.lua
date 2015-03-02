-- localize globals
local loadstring = loadstring
local tostring = tostring
local tostringall = tostringall
local setfenv = setfenv
local pcall = pcall
local pairs = pairs
local type = type
local unpack = unpack
local select = select
local getmetatable = getmetatable
local setmetatable = setmetatable

--- Applies function f to key-value pairs of table t.
-- @param f the function
-- @param t the table
-- @param meta if true, then t's metatable's __index metamethod is also iterated, if it is a table
-- @return the keys for which f returned true
local function metaIter(f, t, meta)
   if not t then t = ENV end
   if meta == nil then meta = true end
   local ret = {}
   if meta then
      local mt = getmetatable(t)
      if mt then
         local idx = mt.__index
         if idx and type(idx) == "table" then
            for k, v in pairs(metaIter(f, idx, meta)) do
               ret[#ret + 1] = k
            end
         end
      end
   end
   for k, v in pairs(t) do if f(k, v) then ret[#ret + 1] = k end end
   return ret
end

--- Hides the REPL frame.
local function hideREPL()
   REPL:Hide()
end

--- Environment in which user code is executed with some convenience functions defined.
local ENV = setmetatable(
   {
      print = function (...)
         REPL_msg:AddMessage(strjoin("\n", tostringall(...)))
      end,
      printf = function(str, ...) ENV.print(format(str, ...)) end,
      clear = function () REPL_msg:Clear() end,
      quit = hideREPL,
      exit = hideREPL,
      methods = function (t, deep)
         if deep == nil then deep = true end
         return metaIter(
            function (k, v) return type(v) == "function" end,
            t,
            deep
         )
      end,
      constants = function (t, deep)
         return metaIter(
            function (k, v)
               return type(k) == "string" and k:find("^[%u_][%u%d_]*$")
            end,
            t,
            deep
         )
      end,
      hasmetatable = function (t, mt) return getmetatable(t) == mt end,
      table = setmetatable(
         {
            keys = function (t)
               local ret = {}
               for k, _ in pairs(t) do ret[#ret + 1] = k end
               return ret
            end,
            values = function (t)
               local ret = {}
               for _, v in pairs(t) do ret[#ret + 1] = v end
               return ret
            end,
            invert = function (t)
               local ret = {}
               for k, v in pairs(t) do ret[v] = k end
               return ret
            end,
            merge = function (t1, t2)
               for k, v in pairs(t2) do t1[k] = v end
               return t1
            end,
            size = function (t)
               local i = 0
               for _, _ in pairs(t) do i = i + 1 end
               return i
            end,
            isempty = function (t)
               for _, _ in pairs(t) do return false end
               return true
            end
         },
         {__index = table}
      ),
      string = setmetatable(
         {subn = function (str, i, n) return str:sub(i, i + n) end},
         {__index = string}
      )
   },
   {__index = _G}
)

-- pretty printing
do
   local BLACK          = "|cff000000"
   local RED            = "|cffcd0000"
   local GREEN          = "|cff00cd00"
   local YELLOW         = "|cffcdcd00"
   local BLUE           = "|cff0000ee"
   local MAGENTA        = "|cffcd00cd"
   local CYAN           = "|cff00cdcd"
   local GRAY           = "|cffe5e5e5"
   local DARKGRAY       = "|cfff7f7f7"
   local BRIGHT_RED     = "|cffff0000"
   local BRIGHT_GREEN   = "|cff00ff00"
   local BRIGHT_YELLOW  = "|cffffff00"
   local BRIGHT_BLUE    = "|cff5c5cff"
   local BRIGHT_MAGENTA = "|cffff00ff"
   local BRIGHT_CYAN    = "|cff00ffff"
   local BRIGHT_WHITE   = "|cffffffff"

   --- Colorizes a string.
   -- @param color the color code
   -- @param str the string
   -- @return the colorized string
   local function colorize(color, str) return color..str.."|r" end

   --- Pretty-prints a lua value.
   -- @param x the value to pretty-print
   local function pretty(x)
      local t = type(x)
      if t == "string" then
         return "\""..MAGENTA..format("%q", x:gsub("|", "||")):sub(2, -2).."|r\""
      elseif t == "number" then
         return colorize(CYAN, tostring(x))
      elseif t == "boolean" then
         if x then return colorize(GREEN, tostring(x)) end
         return colorize(RED, tostring(x))
      elseif t == "nil" then
         return colorize(BRIGHT_RED, tostring(x))
      elseif t == "table" then
         local elems = {}
         for k, v in pairs(x) do
            local str
            -- prevent infinite recursion
            if v == x then
               str = RED.."...|r"
            else
               str = pretty(v)
            end
            elems[#elems + 1] = GREEN.."[|r"..pretty(k)..GREEN.."]|r = "..str
         end
         local mt = getmetatable(x)
         if mt then
            elems[#elems + 1] = GREEN.."#<|r"..BRIGHT_GREEN.."metatable|r"..GREEN..">|r = "..pretty(mt)
         end
         return BRIGHT_GREEN.."{|r"..table.concat(elems, ", ")..BRIGHT_GREEN.."}|r"
      end
      local str = tostring(x)
      local i = str:find(": ")
      return GREEN.."#<|r"..colorize(BRIGHT_GREEN, str:sub(1, i - 1))..GREEN..":|r"..colorize(YELLOW, str:sub(i + 2))..GREEN..">|r"
   end

   --- Buffer used for multi-line input.
   local buffer
   local lineNumber = 1
   local function unpackn(...) return select("#", ...) - 1, {...} end

   REPL_EditBox:SetScript(
      "OnEnterPressed",
      function (self)
         REPL_msg:ScrollToBottom()
         lineNumber = lineNumber + 1
         -- Replace leading '=' with 'return '
         local text = self:GetText():gsub("^=", "return ", 1)
         self:AddHistoryLine(text)
         self:SetText("")

         local prompt = "(REPL):"..tostring(lineNumber - 1)
         -- If buffer isn't empty, append to it.
         if buffer then
            buffer = strjoin("\n", buffer, text)
            REPL_msg:AddMessage(prompt.."* "..text)
         else
            buffer = text
            REPL_msg:AddMessage(prompt.."> "..text)
         end

         -- Parse input.
         local func, errorMessage = loadstring(buffer, prompt)
         if not func then
            -- Return if line is incomplete. Next line will be added to buffer.
            if errorMessage:sub(-7, -1) == "'<eof>'" then
               return
            end
            -- Else, print the error, clear the buffer, and return.
            REPL_msg:AddMessage(colorize(RED, errorMessage))
            buffer = nil
            return
         end

         -- Clear the buffer.
         buffer = nil

         -- Set the user code's environment to ENV.
         setfenv(func, ENV)
         -- Call the user's code and get its return values.
         local numReturns, ret = unpackn(pcall(func))
         -- If there's an error, print it and return.
         if not ret[1] then
            REPL_msg:AddMessage(colorize(RED, ret[2]))
            return
         end
         -- If there are no return values, we're done.
         if numReturns == 0 then return end

         -- Pretty-print return values.
         local retPretty = {}
         for i = 1, numReturns do
            retPretty[#retPretty + 1] = pretty(ret[i + 1])
         end
         REPL_msg:AddMessage(BLUE.."#=>|r "..table.concat(retPretty, ", "))
      end
   )
end

-- tab completion
do
   local OPs = {"%+", "%-", "%*", "/", "%%", "%^", "==", "~=", "<=", ">=", "<", ">", "=", "%.%.", ","}
   local function findanyOP(str)
      for i = 1, #OPs do if str:find(OPs[i].."%s?$") then return true end end
      return false
   end

   local KWs = {"and", "elseif", "if", "not", "or", "return", "until", "while", "end"}
   local function findanyKW(str)
      for i = 1, #KWs do if str:find("%s"..KWs[i].." $") then return true end end
      return false
   end

   local NAME_PATTERN_FIRST = "[%a_]"
   local NAME_PATTERN_REST = "[%w_]*"
   local NAME_PATTERN = "("..NAME_PATTERN_FIRST..NAME_PATTERN_REST..")"
   local NAME_PATTERN_ONLY = "^"..NAME_PATTERN.."$"

   local autocomplete = {
      index = nil,
      prefix = nil,
      suggestions = nil,
      num = 0,
      add = function (self, suggestion)
         local num = self.num + 1
         self.suggestions[num] = suggestion
         self.num = num
      end,
      findKeys = function (self, t, options)
         local keyType = options.keyType
         local pattern = options.pattern
         local incompleteKey = options.incompleteKey
         local quote = options.quote == true
         local i
         if incompleteKey then i = #incompleteKey + 1 end
         for k, _ in pairs(t) do
            local kstr = tostring(k)
            if (not keyType or type(k) == keyType) and
               (not pattern or kstr:find(pattern)) and
               (not incompleteKey or kstr:sub(1, i - 1) == incompleteKey) then
               if quote then kstr = format("%q", kstr) end
               if incompleteKey then kstr = kstr:sub(i) end
               self:add(kstr)
            end
         end
      end,
      init = function (self, text)
         self.prefix = text
         self.suggestions = {}

         -- suggest globals after an operator or keyword
         if findanyOP(text) or findanyKW(text) then
            local envs = {ENV, _G}
            for i = 1, #envs do
               self:findKeys(
                  envs[i], {keyType = "string", pattern = NAME_PATTERN_ONLY}
               )
            end
         end

         -- suggest globals after an incomplete name
         local incompleteKey = text:match(NAME_PATTERN.."$")
         if incompleteKey then
            local envs = {ENV, _G}
            for i = 1, #envs do
               self:findKeys(
                  envs[i],
                  {
                     keyType = "string",
                     incompleteKey = incompleteKey,
                     pattern = "^"..incompleteKey..NAME_PATTERN_REST.."$"
                  }
               )
            end
         end

         -- suggest name keys after a dot operator
         local tableName = text:match(NAME_PATTERN.."%.$")
         if tableName then
            local t = ENV[tableName]
            if t then
               self:findKeys(t, {keyType = "string", pattern = NAME_PATTERN_ONLY})
            end
         end

         -- suggest matching name keys after dot and incomplete name
         tableName, incompleteKey =
            text:match(NAME_PATTERN.."%."..NAME_PATTERN.."$")
         if tableName then
            local t = ENV[tableName]
            if t then
               self:findKeys(
                  t,
                  {
                     keyType = "string",
                     incompleteKey = incompleteKey,
                     patterns = "^"..incompleteKey..NAME_PATTERN_REST.."$"
                  }
               )
            end
         end

         -- suggest all keys after [ operator
         tableName = text:match(NAME_PATTERN.."%[$")
         if tableName then
            local t = ENV[tableName]
            if t then
               self:findKeys(t, {keyType = "string", quote = true})
               self:findKeys(t, {keyType = "boolean"})
               self:findKeys(t, {keyType = "number"})
            end
         end

         -- suggest matching string keys after [ and incomplete string
         tableName, incompleteKey = text:match(NAME_PATTERN.."%[\"([^\"]*)$")
         if tableName then
            local t = ENV[tableName]
            if t then
               self:findKeys(
                  t,
                  {
                     keyType = "string",
                     incompleteKey = incompleteKey,
                     quote = true
                  }
               )
            end
         end

         -- suggest matching numeric keys after [ and number
         tableName, incompleteKey = text:match(NAME_PATTERN.."%[(%d+)$")
         if tableName then
            local t = ENV[tableName]
            if t then
               self:findKeys(t, {keyType = "number", incompleteKey = incompleteKey})
            end
         end

         self.index = 1
      end
   }

   REPL_EditBox:SetScript(
      "OnTabPressed",
      function (self)
         if not autocomplete.suggestions then
            autocomplete:init(self:GetText())
         end
         if autocomplete.num == 0 then return end

         self:SetText(
            autocomplete.prefix..autocomplete.suggestions[autocomplete.index]
         )

         if IsShiftKeyDown() then
            autocomplete.index = autocomplete.index - 1
            if autocomplete.index == 0 then
               autocomplete.index = autocomplete.num
            end
         else
            autocomplete.index = autocomplete.index + 1
            if autocomplete.index > autocomplete.num then
               autocomplete.index = 1
            end
         end
      end
   )

   REPL_EditBox:SetScript(
      "OnTextChanged",
      function (self, userInput)
         if userInput then autocomplete.suggestions = nil end
      end
   )
end

REPL.TitleText:SetText("REPL")

-- wheel scrolling
REPL_msg:SetScript(
   "OnMouseWheel",
   function (self, delta)
      if delta > 0 then
         self:ScrollUp()
      elseif delta < 0 then
         self:ScrollDown()
      end
   end
)
REPL_msg:EnableMouseWheel(true)

SLASH_REPL1 = "/repl"
function SlashCmdList.REPL() REPL:Show() end

local _, title = GetAddOnInfo("REPL")
REPL_msg:AddMessage(
   title.." v"..GetAddOnMetadata("REPL", "Version").." (".._VERSION..")"
)
