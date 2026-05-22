-- pi-chat.nvim — Interactive chat with Pi coding agent in Neovim

local M = {}

-- ─── Config ───────────────────────────────────────────────────────────────

local config = {
  keymap = "<leader>pc",          -- toggle chat
  keymap_explain = "<leader>pe",  -- explain selection
  height = 18,
  model = nil,                    -- nil = default from settings, or "provider/id"
  pi_cmd = nil,                   -- built in setup() based on model
  include_file_context = true,
  max_context_lines = 200,
}

-- ─── State ────────────────────────────────────────────────────────────────

local state = {
  chat_win = nil,
  input_win = nil,
  chat_buf = nil,
  input_buf = nil,
  editor_win = nil,
  editor_buf = nil,
  job_id = nil,
  is_streaming = false,
  messages = {},
  current_text = "",
  ns_id = nil,
}

-- ─── Highlights ───────────────────────────────────────────────────────────

local function setup_highlights()
  local groups = {
    PiChatUser = { fg = "#58A6FF", bold = true },
    PiChatAgent = { fg = "#E3D09C" },
    PiChatSystem = { fg = "#8B949E" },
    PiChatBold = { fg = "#E3D09C", bold = true },
    PiChatCode = { fg = "#79C0FF", bg = "#1c1c1c" },
    PiChatHeading = { fg = "#58A6FF", bold = true },
    PiChatSelection = { fg = "#79C0FF", bg = "#1c1c1c" },
  }
  for name, attrs in pairs(groups) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

-- ─── Helpers ──────────────────────────────────────────────────────────────

local function ensure_modifiable()
  if state.chat_buf then
    vim.bo[state.chat_buf].modifiable = true
  end
end

local function ensure_readonly()
  if state.chat_buf then
    vim.bo[state.chat_buf].modifiable = false
  end
end

-- ─── Build Pi Command ─────────────────────────────────────────────────────

local function build_pi_cmd()
  local cmd = { "pi", "--mode", "rpc", "--no-session" }
  if config.model then
    table.insert(cmd, "--model")
    table.insert(cmd, config.model)
  end
  return cmd
end

-- ─── Process ──────────────────────────────────────────────────────────────

local function start_pi()
  if state.job_id then return true end

  local on_stdout = function(_, data)
    for _, line in ipairs(data) do
      if line and line ~= "" then
        M._handle_event(line)
      end
    end
  end

  local on_exit = function(_, code, _)
    state.job_id = nil
    if code ~= 0 then
      M._append_chat("", "⚠ Pi exited with code " .. code, "PiChatSystem")
    end
  end

  config.pi_cmd = build_pi_cmd()
  state.job_id = vim.fn.jobstart(config.pi_cmd, {
    rpc = false,
    pty = false,
    on_stdout = on_stdout,
    on_stderr = on_stdout,
    on_exit = on_exit,
  })

  if state.job_id <= 0 then
    vim.notify("Failed to start Pi", vim.log.levels.ERROR)
    return false
  end

  local model_info = config.model and ("model: " .. config.model) or "model: default"
  M._append_chat("", "▸ Connected (" .. model_info .. ")", "PiChatSystem")
  return true
end

-- ─── Events ───────────────────────────────────────────────────────────────

function M._handle_event(raw_line)
  local ok, event = pcall(vim.json.decode, raw_line)
  if not ok then return end
  if not event or not event.type then return end

  if event.type == "message_update" and event.assistantMessageEvent then
    local delta = event.assistantMessageEvent.delta
    if delta and delta.type == "text_delta" and delta.text then
      state.current_text = state.current_text .. delta.text
      M._redraw_current()
    end

  elseif event.type == "message_end" and event.message then
    local msg = event.message
    if msg.role == "assistant" then
      local text = ""
      if msg.content then
        for _, part in ipairs(msg.content) do
          if part.type == "text" then text = text .. part.text end
        end
      end
      if text ~= "" then
        state.current_text = ""
        table.insert(state.messages, { role = "assistant", content = text })
        M._append_chat("Pi", text, "PiChatAgent")
        M._append_separator()
      end
      state.is_streaming = false
      M._update_status()
    end

  elseif event.type == "agent_end" then
    state.is_streaming = false
    state.current_text = ""
    M._update_status()

  elseif event.type == "response" and event.command == "prompt" then
    if not event.success then
      M._append_chat("", "⚠ Prompt rejected", "PiChatSystem")
      state.is_streaming = false
      M._update_status()
    end
  end
end

-- ─── Simple Markdown Renderer ─────────────────────────────────────────────

local function render_markdown_lines(text, hl_group)
  local lines = vim.split(text, "\n")
  local result = {}

  for _, line in ipairs(lines) do
    local applied_hl = hl_group

    if line:match("^#+ ") then
      applied_hl = "PiChatHeading"
    elseif line:match("^```") then
      applied_hl = "PiChatCode"
    elseif line:match("%*%*.-%*%*") or line:match("__.-__") then
      applied_hl = "PiChatBold"
    elseif line:match("^%s*[-*] ") then
      applied_hl = hl_group
    end

    table.insert(result, { line, applied_hl })
  end

  return result
end

-- ─── UI ───────────────────────────────────────────────────────────────────

local function create_chat_window()
  state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.chat_buf].buftype = "nofile"
  vim.bo[state.chat_buf].modifiable = false

  state.ns_id = vim.api.nvim_create_namespace("pi-chat")

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype = "nofile"

  state.editor_win = vim.api.nvim_get_current_win()
  state.editor_buf = vim.api.nvim_win_get_buf(state.editor_win)

  vim.cmd(string.format("belowright %dsplit", config.height))
  state.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)

  vim.cmd("belowright 2split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)

  vim.api.nvim_set_current_win(state.input_win)
  vim.cmd("startinsert")

  vim.api.nvim_set_option_value("wrap", true, { win = state.chat_win })
  vim.api.nvim_set_option_value("number", false, { win = state.chat_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = state.chat_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = state.chat_win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = state.chat_win })
  vim.api.nvim_set_option_value("cursorline", true, { win = state.input_win })

  vim.keymap.set("i", "<CR>", M.send_message, { buffer = state.input_buf, nowait = true, noremap = true })
  vim.keymap.set("n", "q", M.close, { buffer = state.input_buf, nowait = true })

  M._update_status()
  setup_highlights()
end

function M._append_separator()
  if not state.chat_buf then return end
  ensure_modifiable()
  vim.api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { "─────────────────────────────────────────" })
  ensure_readonly()
end

function M._append_chat(prefix, text, hl_group)
  if not state.chat_buf then return end

  local full_text
  if prefix and prefix ~= "" and text ~= "" then
    full_text = prefix .. ": " .. text
  elseif prefix and prefix ~= "" then
    full_text = prefix
  else
    full_text = text
  end

  local rendered = render_markdown_lines(full_text, hl_group)

  ensure_modifiable()
  local start_line = vim.api.nvim_buf_line_count(state.chat_buf)
  local text_lines = {}
  for _, entry in ipairs(rendered) do
    table.insert(text_lines, entry[1])
  end
  vim.api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, text_lines)

  for i, entry in ipairs(rendered) do
    if entry[2] then
      vim.api.nvim_buf_add_highlight(state.chat_buf, state.ns_id, entry[2], start_line + i - 1, 0, -1)
    end
  end
  ensure_readonly()

  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_set_cursor(state.chat_win, { vim.api.nvim_buf_line_count(state.chat_buf), 0 })
  end
end

function M._redraw_current()
  if not state.chat_buf then return end

  local lc = vim.api.nvim_buf_line_count(state.chat_buf)
  if lc > 0 then
    ensure_modifiable()
    vim.api.nvim_buf_set_lines(state.chat_buf, lc - 1, -1, false, {})
    ensure_readonly()
  end

  M._append_chat("Pi", state.current_text, "PiChatAgent")
end

function M._update_status()
  if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win) then return end
  local status = state.is_streaming and " ⏳ Thinking..." or " ▸ Ready"
  if state.editor_buf and vim.api.nvim_buf_is_valid(state.editor_buf) then
    local filepath = vim.api.nvim_buf_get_name(state.editor_buf)
    if filepath ~= "" then
      status = status .. " — " .. vim.fn.fnamemodify(filepath, ":~:.")
    end
  end
  vim.api.nvim_set_option_value("statusline", " Pi Chat" .. status .. " — Enter/Esc ", { win = state.input_win })
end

-- ─── File Context ─────────────────────────────────────────────────────────

local function get_current_file_info()
  if not config.include_file_context then return "" end

  local buf = state.editor_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return "" end

  local filepath = vim.api.nvim_buf_get_name(buf)
  if filepath == "" then return "" end

  local relpath = vim.fn.fnamemodify(filepath, ":~:.")
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local max_lines = math.min(total_lines, config.max_context_lines)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, max_lines, false)
  local content = table.concat(lines, "\n")
  local truncated = total_lines > max_lines and string.format("\n... (%d more lines)", total_lines - max_lines) or ""

  return string.format(
    "\n\n--- Context: %s (%d lines) ---\n```\n%s%s\n```",
    relpath, total_lines, content, truncated
  )
end

-- ─── Selection Context ────────────────────────────────────────────────────

local function get_selection_context()
  if not state.editor_buf or not vim.api.nvim_buf_is_valid(state.editor_buf) then
    return "", ""
  end

  -- Try visual selection
  local start_line, end_line, start_col, end_col

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "" then
    -- Get visual marks
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    start_line = start_pos[2]
    end_line = end_pos[2]
    start_col = start_pos[3]
    end_col = end_pos[3]
  else
    -- No selection
    return "", ""
  end

  if start_line == 0 or end_line == 0 then
    return "", ""
  end

  local lines = vim.api.nvim_buf_get_lines(state.editor_buf, start_line - 1, end_line, false)
  local selected_text = table.concat(lines, "\n")

  local filepath = vim.api.nvim_buf_get_name(state.editor_buf)
  local relpath = vim.fn.fnamemodify(filepath, ":~:.")

  local context = string.format(
    "\n\n--- Selected lines %d–%d in %s ---\n```\n%s\n```",
    start_line, end_line, relpath, selected_text
  )

  local display = string.format("[selected: lines %d–%d in %s]", start_line, end_line, relpath)

  return context, display
end

-- ─── Public API ───────────────────────────────────────────────────────────

function M.toggle()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    M.close()
  else
    M.open()
  end
end

function M.open()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then return end

  create_chat_window()
  if not start_pi() then M.close(); return end

  for _, msg in ipairs(state.messages) do
    if msg.role == "user" then
      M._append_chat("You", msg.content, "PiChatUser")
    else
      M._append_chat("Pi", msg.content, "PiChatAgent")
    end
    M._append_separator()
  end
end

function M.close()
  if vim.fn.mode() == "i" then vim.cmd("stopinsert") end
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_close(state.chat_win, true)
  end
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end
  state.chat_win = nil
  state.input_win = nil
  state.chat_buf = nil
  state.input_buf = nil
  if state.editor_win and vim.api.nvim_win_is_valid(state.editor_win) then
    vim.api.nvim_set_current_win(state.editor_win)
  end
end

function M.send_message(extra_context, extra_display)
  if not state.input_buf then return end

  local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
  local msg = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")
  if msg == "" then return end

  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  local file_context = get_current_file_info()
  local selection_context = extra_context or ""
  local full_msg = msg .. selection_context .. file_context

  -- Display in chat
  local display_msg = msg
  if extra_display and extra_display ~= "" then
    display_msg = display_msg .. " " .. extra_display
  end
  M._append_chat("You", display_msg, "PiChatUser")

  table.insert(state.messages, { role = "user", content = display_msg })

  state.is_streaming = true
  state.current_text = ""
  M._update_status()

  local json = vim.json.encode({ type = "prompt", message = full_msg })
  vim.fn.chansend(state.job_id, json .. "\n")
end

-- ─── Explain Selection ────────────────────────────────────────────────────

function M.explain_selection()
  -- Get selection
  local sel_context, sel_display = get_selection_context()
  if sel_context == "" then
    vim.notify("No selection. Visually select text first, then use this command.", vim.log.levels.WARN)
    return
  end

  -- Build message
  local msg = "Explain what this code does:"

  -- Open chat if not open
  if not state.chat_win or not vim.api.nvim_win_is_valid(state.chat_win) then
    M.open()
  end

  if not state.job_id then
    vim.notify("Pi not connected", vim.log.levels.ERROR)
    return
  end

  -- Send directly (skip input buffer)
  local file_context = get_current_file_info()
  local full_msg = msg .. sel_context .. file_context

  M._append_chat("You", msg .. " " .. sel_display, "PiChatUser")
  table.insert(state.messages, { role = "user", content = msg .. " " .. sel_display })

  state.is_streaming = true
  state.current_text = ""
  M._update_status()

  local json = vim.json.encode({ type = "prompt", message = full_msg })
  vim.fn.chansend(state.job_id, json .. "\n")
end

-- ─── Setup ────────────────────────────────────────────────────────────────

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  vim.keymap.set("n", config.keymap, M.toggle, {
    desc = "Toggle Pi Chat",
    noremap = true,
    silent = true,
  })

  vim.keymap.set("v", config.keymap_explain, M.explain_selection, {
    desc = "Explain selection in Pi Chat",
    noremap = true,
    silent = true,
  })

  vim.api.nvim_create_user_command("PiChat", M.toggle, { desc = "Toggle Pi Chat" })
  vim.api.nvim_create_user_command("PiChatClose", M.close, { desc = "Close Pi Chat" })
  vim.api.nvim_create_user_command("PiExplain", M.explain_selection, { desc = "Explain visual selection" })
end

return M
