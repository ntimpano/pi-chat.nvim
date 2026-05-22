# pi-chat.nvim

Interactive chat with [Pi coding agent](https://github.com/earendil-works/pi-coding-agent) right inside Neovim.

## Features

- 💬 Chat with Pi in a vertical split
- ⌨️ `Enter` to send, `Esc`/`q` to close
- 🔄 Persistent Pi process across messages
- ⏳ Live streaming response updates
- 📋 Conversation history preserved

## Demo

```
┌──────────────────────────────────────────────────────┐
│  Neovim Editor          │ Pi Chat  ▸ Ready           │
│                           │                           │
│  Your code here...        │ You: explain this file    │
│                           │                           │
│                           │ Pi: This is a ...         │
│                           │                           │
│───────────────────────────│────────────────────────── │
│                           │ Pi Chat — Enter/Esc       │
└──────────────────────────────────────────────────────┘
```

## Installation

### lazy.nvim

```lua
{
  "ntimpano/pi-chat.nvim",
  keys = {
    { "<leader>pc", function() require("pi-chat").toggle() end, desc = "Toggle Pi Chat" },
  },
  config = function()
    require("pi-chat").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "ntimpano/pi-chat.nvim",
  config = function()
    require("pi-chat").setup()
    vim.keymap.set("n", "<leader>pc", function() require("pi-chat").toggle() end)
  end,
}
```

## Usage

| Key | Action |
|-----|--------|
| `<leader>pc` | Open/close chat |
| `Enter` (in input) | Send message |
| `Esc` / `q` | Close chat |

## Configuration

```lua
require("pi-chat").setup({
  keymap = "<leader>pc",       -- toggle keybinding
  width = 80,                   -- chat panel width
  pi_cmd = { "pi", "--mode", "rpc", "--no-session" },  -- Pi command
})
```

## Requirements

- Neovim >= 0.9
- [Pi coding agent](https://github.com/earendil-works/pi-coding-agent) installed and configured

## License

MIT
