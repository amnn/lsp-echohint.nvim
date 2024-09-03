# lsp-echohint.nvim

Plugin for displaying the inlay hints for the current line in the echo area.

<p align="center">
<img width="497" alt="lua" src="https://github.com/user-attachments/assets/893680f7-4be5-49a9-bc62-ca1539eefa81">
<img width="497" alt="rust" src="https://github.com/user-attachments/assets/22b135a9-28ab-4133-8793-82f8158c4535">
<img width="497" alt="tsx" src="https://github.com/user-attachments/assets/2438eedf-3edf-42fb-8719-9a0c2fa504c1">
</p>

*(Left to right, top to bottom, click to zoom in) Lua, Rust, TypeScript (TSX). [Theming](https://github.com/amnn/nvim/blob/7219c529e2f25efc039eaf2f3947cc2e086f4792/lua/plugins/theming.lua): [modus-operandi](https://github.com/miikanissi/modus-themes.nvim), [lualine.nvim (ayu)](https://github.com/nvim-lualine/lualine.nvim), [kitty](https://sw.kovidgoyal.net/kitty/).*

## Requirements

- Neovim **0.10+**.
- Language server support for inlay hints.
- Treesitter support (optional) to display source expressions.

## Installation

Install using [lazy.nvim](https://github.com/folke/lazy.nvim),

```lua
{
  "amnn/lsp-echohint.nvim",
  opts = {},
}
```

## Configuration

Explicit configuration is not required, but the following options are
available:

```lua
require("lsp-echohint").setup {
  -- Whether to automatically enable inlay hints if the language server
  -- advertises support for them.
  auto_enable = true,

  -- How to convert the list of hints into a displayable string. The example
  -- below combines all the hints into one string, delimited by " | ", and
  -- prints that with a plain format. The default implementation is similar,
  -- but includes the following additional features:
  --
  --  - Cleans up hints of punctuation (leading and trailing colons).
  --
  --  - Attempts to display the source expressions (usually variables) for
  --    type hints.
  --
  --  - Highlights (roughly) where the cursor is by highlighting the nearest
  --    delimiter in the output.
  --
  --  - Applies the `Identifier` highlight group to source expressions and
  --    parameter hints, the `Type` highlight to type hints, and the
  --    `Delimiter` highlight to surrounding punctuation.
  --
  -- @param line number -- the current line number.
  -- @param hints table -- the list of hints for that line. Each hint is a
  --        table containing:
  --        - label string -- the hint text.
  --        - character number -- the character (column position)
  --        - kind number -- the hint kind (1 = Type, 2 = Parameter).
  --
  -- @return table -- a list of { text, highlight } pairs, to be passed to
  --         `vim.api.nvim_echo`.
  display = function(line, hints)
    local output = vim.iter(hints)
      :map(function(hint) return hint.label end)
      :join(" | ")

    return { { output, "Normal" } }
  end
}
```

## Related Plugins

There are a couple of plugins (listed below) that provide related functionality
(alternative ways of displaying inlay hints), typically by displaying them at
the end of the line. This plugin tries to combine the parts I found most useful
from both of these plugins (credited below), while also providing an even more
pared down experience, as I find it too distracting to see hints on every line,
all the time.

- [chrisgrieser/nvim-lsp-endhints](https://github.com/chrisgrieser/nvim-lsp-endhints):
  I used this plugin as a reference for the `textDocument/inlayHint` callback,
  the logic for detecting server support for inlay hints and auto-enabling the
  feature, the clean-ups of leading and trailing colons, and the GitHub
  workflows for managing a Neovim plugin repository.
- [felpafel/inlay-hint.nvim](https://github.com/felpafel/inlay-hint.nvim): I
  borrowed the idea of exposing a display callback from this plugin, as well
  as the idea of extracting the source expression using treesitter.

## FAQ

### How do I enable inlay hints for my language server?

Please take a look at my [personal configuration](https://github.com/amnn/nvim/blob/7219c529e2f25efc039eaf2f3947cc2e086f4792/lua/plugins/lsp.lua#L124-L171)
for an example of enabling inlay hints across some common language servers.

### How do I display all inlay hints for a file?

Take a look at the [Related Plugins](#related-plugins) for plugins that offer
other ways to display inlay hints. Alternatively, simply enabling inlay hints
using

```lua
vim.api.inlay_hint.enable(true)
```

will enable it for your current buffer, and the default rendering will display
hints inline (as originally intended), and this can be done automatically by
adding the following autocmd to your configuration:

```lua
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("EnableInlayHints", { clear = true }),
  desc = "Enable inlay hints if the server supports them",
  callback = function(ctx)
    local client = ctx.data.client_id
      and vim.lsp.get_client_by_id(ctx.data.client_id)
    if not client then return end

    if client.server_capabilities.inlayHintProvider then
      vim.lsp.inlay_hint.enable(true, { bufnr = ctx.buf })
    end
  end,
})
```

## Contributing

Contributions are very welcome! If you notice a bug, try updating to the latest
version and if it is still there please share a report as an issue, with:

- Details on your configuration (operating system, Neovim version, minimal
  init.vim, version or git revision of `lsp-echohint.nvim`).
- The sequence of actions you took.
- The expected outcome.
- The actual outcome, with screenshots if relevant.

If you are interested in working on features please take a look at current
[open issues](https://github.com/amnn/lsp-echohint.nvim/issues) for
inspiration!
