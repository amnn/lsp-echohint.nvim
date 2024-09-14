local M = {}

---Try and find a treesitter node near `line` and `character` and get its
---contents as a string to use as the value part of a `value: type` hint.
---
---If the value is too long or contains newlines, it is truncated by replacing
---newlines with spaces, and limiting the overall length to 20 characters
---(including an ellipsis).
local function value_hint(line, character)
  local node = vim.treesitter.get_node { pos = { line - 1, character - 1 } }
  if not node then return end

  local text = vim.treesitter.get_node_text(node, 0)
  if #text > 20 or text:match "\n" then
    return text:gsub("\n *", " "):sub(1, 17) .. "..."
  else
    return text
  end
end

---@alias EchoText [string, string]

---@class EchoHint
---@field label string     -- the text to display. If the underlying hint was
---                           composed of label parts, this will be the
---                           concatenation of all of them.
---@field character number -- the character offset in the line.
---@field kind number      -- the hint kind. 1 = Type, 2 = Parameter

---@alias LspEchoHint.Display fun(line: number, hints: EchoHint[]): EchoText[]?

---Default display function for inlay hints. Accepts a list of hints for the
---line and returns a list of pairs of text and its highlight group.
---
---The default display adds the following features:
---
--- - Cleans up hints of punctuation (leading and trailing colons).
--- - Attempts to display the name of the value (mainly variable) that a type
---   hint is for, using treesitter.
--- - Highlights (roughly) where the cursor is by highlighting the nearest
---   delimiter in the output
---
---@param line number
---@param hints EchoHint[]
---@return EchoText[]?
local function display(line, hints)
  local col = vim.api.nvim_win_get_cursor(0)[2]

  local last = 0
  local tokens = {}
  local prefix = "["

  for _, hint in ipairs(hints) do
    local at_cursor = last <= col and col < hint.character
    local highlight = at_cursor and "Cursor" or "Normal"

    table.insert(tokens, { prefix, highlight })
    table.insert(tokens, { " ", "Normal" })

    -- Some language servers (e.g. Rust Analyzer) return hints with
    -- colons to represent type annotations (leading colon), or parameter
    -- names (trailing colon). Remove them, because we are not displaying
    -- the hint inline.
    local label = hint.label
    label = vim.trim(label:gsub("^:", ""):gsub(":$", ""))

    -- If this is a type hint, try to find the expression that this type
    -- corresponds to, using treesitter.
    if hint.kind == 1 then
      local value = value_hint(line, hint.character)

      if value then
        table.insert(tokens, { value, "Identifier" })
        table.insert(tokens, { ": ", "Delimiter" })
      end

      table.insert(tokens, { label, "Type" })
    else
      table.insert(tokens, { label, "Identifier" })
    end

    table.insert(tokens, { " ", "Normal" })
    last = hint.character
    prefix = "|"
  end

  local highlight = last <= col and "Cursor" or "Normal"
  table.insert(tokens, { "]", highlight })
  return tokens
end

---@class LspEchoHint.Config
---@field auto_enable boolean?
---@field display LspEchoHint.Display?
local default_config = {
  auto_enable = true,
  display = display,
}

---Handler for textDocument/inlayHint that sets a buffer-local variable with a
---mapping from line numbers to a list of hints on that line, in character
---order.
---
---https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_inlayHint
---
---@param err lsp.ResponseError?
---@param res lsp.InlayHint[]
---@param ctx lsp.HandlerContext
---@param _ table
local function gather_inlay_hints(err, res, ctx, _)
  local hints = {}
  local buf = ctx.bufnr or -1
  local client = vim.lsp.get_client_by_id(ctx.client_id)

  if
    res
    and not err
    and vim.api.nvim_buf_is_valid(buf)
    and client
    and client.server_capabilities.inlayHintProvider
  then
    -- Sort the results by character position so that when we gather them
    -- up into lines, we process hints in the order they should appear in
    -- the line.
    table.sort(
      res,
      function(a, b) return a.position.character < b.position.character end
    )

    for _, hint in ipairs(res) do
      local label = hint.label
      if type(label) ~= "string" then
        -- If the label is an InlayHintLabelPart[], gather all the labels within it.
        label = vim
          .iter(label)
          :map(function(part) return part.value end)
          :join ""
      end

      local line = hint.position.line + 1
      local token =
        { label = label, character = hint.position.character, kind = hint.kind }

      if not hints[line] then hints[line] = {} end
      table.insert(hints[line], token)
    end
  end

  -- Set the new hints -- we build them up first and then set them in one go to
  -- prevent the UI from displaying incomplete information. We also set them
  -- even if the response is an error, to prevent the UI from getting stuck
  -- displaying stale information.
  vim.b[buf].inlay_hints = hints
end

---Setup displaying inlay hints in the echo area.
---@param config LspEchoHint.Config
function M.setup(config)
  config = vim.tbl_deep_extend("force", default_config, config)

  vim.lsp.handlers["textDocument/inlayHint"] = gather_inlay_hints

  local show_hints_group =
    vim.api.nvim_create_augroup("ShowInlayHints", { clear = true })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = show_hints_group,
    desc = "Show the inlay hints for the current line",
    callback = function(_)
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local hints = vim.b.inlay_hints

      -- If the current line has no hints, explicitly clear the echo area.
      local hint = hints and hints[line]
      if hint == nil or hint == vim.NIL or #hint == 0 then
        vim.api.nvim_echo({}, false, {})
        return
      end

      local tokens = config.display(line, hint) or {}
      vim.api.nvim_echo(tokens, false, {})
    end,
  })

  if config.auto_enable then
    vim.api.nvim_create_autocmd("LspAttach", {
      group = show_hints_group,
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
  end
end

return M
