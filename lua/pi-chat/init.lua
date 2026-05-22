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
  width = 80,
  pi_cmd = { "pi", "--mode", "rpc", "--no-session" },
}

-- ─── State ────────────────────────────────────────────────────────────────

local state = {
  win = nil,
  chat_buf = nil,
  input_buf = nil,
  job_id = nil,
  stdin = nil,
  stdout = nil,
  stderr = nil,
  is_streaming = false,
  messages = {},       -- { role, content }
  current_text = "",   -- accumulated streaming text
}

-- ─── Process Management ───────────────────────────────────────────────────

local function start_pi()
  if state.job_id then return end

  local on_stdout = function(_, data)
    for _, line in ipairs(data) do
      if line and line ~= "" then
        M._handle_event(line)
      end
    end
  end

  local on_exit = function(_, code, _)
    state.job_id = nil
    state.stdin = nil
    state.stdout = nil
    state.stderr = nil
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

  -- stdin/stdout file descriptors
  state.stdin = state.job_id
  -- For RPC mode, we write to stdin via chansend
  M._append_chat("▸ Connected to Pi", "Comment")
  return true
end

local function stop_pi()
  if state.job_id then
    vim.fn.chansend(state.stdin, '{"type": "quit"}\n')
    vim.fn.jobstop(state.job_id)
    state.job_id = nil
  end
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
      -- Extract text from message
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
  -- Chat buffer (read-only, shows conversation)
  state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.chat_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.chat_buf })

  -- Input buffer (for typing messages)
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.input_buf })
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  -- Layout: vertical split
  local total_width = vim.o.columns
  local chat_width = math.min(config.width, math.floor(total_width * 0.5))
  local right_col = total_width - chat_width

  -- Create the chat window
  state.win = vim.api.nvim_open_win(state.chat_buf, false, {
    relative = "editor",
    style = "minimal",
    width = chat_width,
    height = vim.o.lines - 3,
    row = 0,
    col = right_col,
    border = "single",
  })

  -- Input window below
  local input_win = vim.api.nvim_open_win(state.input_buf, true, {
    relative = "editor",
    style = "minimal",
    width = chat_width,
    height = 2,
    row = vim.o.lines - 3,
    col = right_col,
    border = "single",
  })

  -- Window options
  vim.api.nvim_set_option_value("wrap", true, { win = state.win })
  vim.api.nvim_set_option_value("cursorline", true, { win = input_win })

  -- Keymaps for input buffer
  vim.keymap.set("i", "<CR>", M.send_message, { buffer = state.input_buf, nowait = true })
  vim.keymap.set("i", "<Esc>", M.close, { buffer = state.input_buf, nowait = true })
  vim.keymap.set("n", "q", M.close, { buffer = state.input_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = state.input_buf, nowait = true })

  -- Status line hint
  vim.api.nvim_set_option_value("statusline", " Pi Chat — Enter to send, Esc to close ", { win = input_win })

  M._update_status()
end

function M._append_chat(text, hl_group)
  if not state.chat_buf then return end

  local lines = vim.split(text, "\n")
  vim.api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, lines)

  if hl_group and hl_group ~= "" then
    local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
    local start = line_count - #lines
    for i, _ in ipairs(lines) do
      vim.api.nvim_buf_add_highlight(state.chat_buf, -1, hl_group, start + i - 1, 0, -1)
    end
  end

  -- Scroll to bottom
  vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.chat_buf), 0 })
end

function M._redraw_current()
  -- Clear the "streaming..." line and redraw current text
  if not state.chat_buf then return end
  local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
  -- Remove last line (previous partial render)
  vim.api.nvim_buf_set_lines(state.chat_buf, line_count - 1, -1, false, {})
  M._append_chat(state.current_text, "")
end

function M._update_status()
  if not state.input_buf then return end
  local status = state.is_streaming and " ⏳ Thinking..." or " ▸ Ready"
  vim.api.nvim_set_option_value("statusline", " Pi Chat" .. status .. " — Enter to send, Esc/q to close ", { win = vim.fn.win_findbuf(state.input_buf)[1] })
end

-- ─── Public API ───────────────────────────────────────────────────────────

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
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
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  local input_wins = vim.fn.win_findbuf(state.input_buf)
  if input_wins and #input_wins > 0 then
    for _, w in ipairs(input_wins) do
      vim.api.nvim_win_close(w, true)
    end
  end

  state.win = nil
  state.chat_buf = nil
  state.input_buf = nil

  -- Don't kill the Pi process — keep it alive for next time
  -- Call stop_pi() if you want to kill it on close
end

function M.send_message()
  if not state.input_buf then return end

  local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
  local msg = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1") -- trim
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
  vim.fn.chansend(state.stdin, json .. "\n")
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
