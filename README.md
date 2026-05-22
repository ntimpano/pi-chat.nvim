# pi-chat.nvim

Chat con [Pi coding agent](https://github.com/earendil-works/pi-coding-agent) dentro de Neovim.

## Features

- 💬 Chat en split horizontal — editor arriba, chat abajo
- ⌨️ `Enter` para enviar, `Esc`/`q` para cerrar
- ⏳ Respuestas en streaming en tiempo real
- 📋 Historial de conversación preservado
- 🎯 Explicar selección visual con `<leader>pe`
- 🤖 Usa el modelo configurado en Pi (no hay que setearlo dos veces)

## Demo

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  Tu editor de código aquí...                     │
│                                                  │
│  ────────────────────────────────────────────── │
│  Pi Chat  ▸ Ready — lua/pi-chat/init.lua        │
│                                                  │
│  You: ¿qué hace esta función?                    │
│  Pi: Esta función configura el chat...           │
│                                                  │
│  ────────────────────────────────────────────── │
│  Pi Chat — Enter to send, Esc/q to close         │
└──────────────────────────────────────────────────┘
```

## Requisitos

### 1. Pi coding agent

Necesitás tener Pi instalado y configurado con al menos un provider con API key:

```bash
# Instalar Pi (si no lo tenés)
npm install -g @earendil-works/pi-coding-agent

# Configurar tu provider
pi --login
```

Verificá que funciona:
```bash
pi --list-models
```

### 2. Modelo

El modelo se configura en **Pi**, no en pi-chat. Pi Chat usa el modelo por defecto que Pi tiene configurado en `~/.pi/agent/settings.json`:

```json
{
  "defaultProvider": "opencode-go",
  "defaultModel": "qwen3.6-plus"
}
```

Si querés cambiar el modelo, usá:
- `/model` dentro de Pi (modo interactivo)
- Editando `settings.json` directamente
- Usando la extensión `pi-agent-name` para identificar tu agente

Pi Chat hereda esa configuración automáticamente. No hace falta configurar el modelo dos veces.

## Instalación

### lazy.nvim

```lua
{
  "ntimpano/pi-chat.nvim",
  keys = {
    { "<leader>pc", function() require("pi-chat").toggle() end, desc = "Toggle Pi Chat" },
    { "<leader>pe", function() require("pi-chat").explain_selection() end, mode = "v", desc = "Explain selection" },
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
    vim.keymap.set("v", "<leader>pe", function() require("pi-chat").explain_selection() end)
  end,
}
```

## Uso

### Chat normal

| Tecla | Acción |
|-------|--------|
| `<leader>pc` | Abrir/cerrar chat |
| `Enter` (en input) | Enviar mensaje |
| `Esc` / `q` | Cerrar chat |

### Explicar código

1. Seleccioná código con `v` o `V`
2. `<leader>pe`
3. Pi responde solo sobre la selección

### Comandos

| Comando | Acción |
|---------|--------|
| `:PiChat` | Toggle chat |
| `:PiChatClose` | Cerrar chat |
| `:PiExplain` | Explicar selección visual |

## Configuración

```lua
require("pi-chat").setup({
  keymap = "<leader>pc",           -- toggle chat
  keymap_explain = "<leader>pe",   -- explain selection (visual mode)
  height = 18,                      -- altura del panel de chat
  include_file_context = true,      -- adjuntar archivo actual a cada mensaje
  max_context_lines = 200,          -- máximo de líneas del archivo a incluir
})
```

> **Nota:** El modelo se configura en Pi, no aquí. Pi Chat usa el modelo por defecto de Pi.

## License

MIT
