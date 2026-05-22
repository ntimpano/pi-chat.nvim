-- pi-chat.nvim — Interactive chat with Pi coding agent in Neovim
--
-- Usage:
--   require('pi-chat').setup()
--   <leader>pc  — toggle chat window
--
-- In chat:
--   Enter — send message
--   Esc / q — close chat
--   Ctrl+c — interrupt current response

local M = {}

-- ─── Config ───────────────────────────────────────────────────────────────

local config = {
  keymap = "<leader>pc",
  height = 18,              -- chat panel height (lines)
  pi_cmd = { "pi", "--mode", "rpc", "--no-session" },
}

-- ─── State ────────────────────────────────────────────────────────────────

local state = {
  chat_win = nil,
  input_win = nil,
  chat_buf = nil,
  input_buf = nil,
  editor_win = nil,
  job_id = nil,
  is_streaming = false,
  messages = {},
  current_text = "",
}

-- ─── Process Management ───────────────────────────────────────────────────

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
      M._append_chat(string.format("⚠ Pi exited with code %d", code), "WarningMsg")
    end
  end

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

  M._append_chat("▸ Connected to Pi", "Comment")
  return true
end

-- ─── Event Handling ───────────────────────────────────────────────────────

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
          if part.type == "text" then
            text = text .. part.text
          end
        end
      end
      if text ~= "" then
        state.current_text = ""
        table.insert(state.messages, { role = "assistant", content = text })
        M._append_chat(text, "")
        M._append_chat("", "")
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
      M._append_chat("⚠ Prompt rejected", "WarningMsg")
      state.is_streaming = false
      M._update_status()
    end
  end
end

-- ─── UI ───────────────────────────────────────────────────────────────────

local function create_chat_window()
  -- Chat buffer (read-only conversation)
  state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.chat_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.chat_buf })

  -- Input buffer
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.input_buf })
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  -- Save editor window to restore later
  state.editor_win = vim.api.nvim_get_current_win()

  -- Split horizontally: chat on bottom
  vim.cmd(string.format("belowright %dsplit", config.height))
  state.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)

  -- Split input below chat
  vim.cmd("belowright 2split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)

  -- Go back to editor
  vim.api.nvim_set_current_win(state.editor_win)

  -- Window options
  vim.api.nvim_set_option_value("wrap", true, { win = state.chat_win })
  vim.api.nvim_set_option_value("number", false, { win = state.chat_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = state.chat_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = state.chat_win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = state.chat_win })
  vim.api.nvim_set_option_value("cursorline", true, { win = state.input_win })

  -- Keymaps for input buffer
  vim.keymap.set("i", "<CR>", M.send_message, { buffer = state.input_buf, nowait = true })
  vim.keymap.set("i", "<Esc>", M.close, { buffer = state.input_buf, nowait = true })
  vim.keymap.set("n", "q", M.close, { buffer = state.input_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = state.input_buf, nowait = true })

  vim.api.nvim_set_option_value("statusline", " Pi Chat — Enter to send, Esc/q to close ", { win = state.input_win })
  M._update_status()
end

function M._append_chat(text, hl_group)
  if not state.chat_buf then return end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.chat_buf })

  local lines = vim.split(text, "\n")
  vim.api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, lines)

  if hl_group and hl_group ~= "" then
    local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
    local start = line_count - #lines
    for i, _ in ipairs(lines) do
      vim.api.nvim_buf_add_highlight(state.chat_buf, -1, hl_group, start + i - 1, 0, -1)
    end
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = state.chat_buf })

  -- Scroll to bottom
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_set_cursor(state.chat_win, { vim.api.nvim_buf_line_count(state.chat_buf), 0 })
  end
end

function M._redraw_current()
  if not state.chat_buf then return end
  local line_count = vim.api.nvim_buf_line_count(state.chat_buf)

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.chat_buf })
  vim.api.nvim_buf_set_lines(state.chat_buf, line_count - 1, -1, false, {})
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.chat_buf })

  M._append_chat(state.current_text, "")
end

function M._update_status()
  if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win) then return end
  local status = state.is_streaming and " ⏳ Thinking..." or " ▸ Ready"
  vim.api.nvim_set_option_value("statusline", " Pi Chat" .. status .. " — Enter to send, Esc/q to close ", { win = state.input_win })
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
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    return
  end

  create_chat_window()

  if not start_pi() then
    M.close()
    return
  end

  -- Show existing conversation
  for _, msg in ipairs(state.messages) do
    if msg.role == "user" then
      M._append_chat("You: " .. msg.content, "Statement")
    else
      M._append_chat("Pi: " .. msg.content, "")
    end
    M._append_chat("", "")
  end
end

function M.close()
  -- Close chat window
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_close(state.chat_win, true)
  end

  -- Close input window
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end

  state.chat_win = nil
  state.input_win = nil
  state.chat_buf = nil
  state.input_buf = nil

  -- Focus back to editor
  if state.editor_win and vim.api.nvim_win_is_valid(state.editor_win) then
    vim.api.nvim_set_current_win(state.editor_win)
  end

  -- Keep Pi process alive
end

function M.send_message()
  if not state.input_buf then return end

  local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
  local msg = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")
  if msg == "" then return end

  -- Clear input
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  -- Show user message
  M._append_chat("You: " .. msg, "Statement")
  M._append_chat("", "")
  table.insert(state.messages, { role = "user", content = msg })

  -- Send to Pi
  state.is_streaming = true
  state.current_text = ""
  M._update_status()

  local json = vim.json.encode({ type = "prompt", message = msg })
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

  vim.api.nvim_create_user_command("PiChat", M.toggle, { desc = "Toggle Pi Chat" })
  vim.api.nvim_create_user_command("PiChatClose", M.close, { desc = "Close Pi Chat" })
end

return M
