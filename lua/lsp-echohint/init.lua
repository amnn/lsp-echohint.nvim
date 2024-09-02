local M = {}

---@class LspEchoHint.Config
---@field auto_enable boolean?
local default_config = {
  auto_enable = true,
}

---Handler for textDocument/inlayHint that sets a buffer-local variable with a
---mapping from line numbers to a list of hints on that line, in character
---order.
---
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_inlayHint
---
---@param err lsp.ResponseError?
---@param res lsp.InlayHint[]
---@param ctx lsp.HandlerContext
---@param _ table
local function gather_inlay_hints(err, res, ctx, _)
  local hints = {}
  local buf = ctx.bufnr or -1
  local client = vim.lsp.get_client_by_id(ctx.client_id)

  if err then
    vim.notify("Inlay Hints Error: " .. vim.inspect(err), vim.log.levels.ERROR)
  elseif
    res
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

      -- Some language servers (e.g. Rust Analyzer) return hints with
      -- colons to represent type annotations (leading colon), or parameter
      -- names (trailing colon). Remove them, because we are not displaying
      -- the hint inline.
      label = vim.trim(label:gsub("^:", ""):gsub(":$", ""))

      -- If this is a type hint, try to find the variable that this type
      -- corresponds to, using treesitter.
      if hint.kind == 1 then
        local node = vim.treesitter.get_node {
          bufnr = buf,
          pos = {
            hint.position.line,
            hint.position.character - 1,
          },
        }

        if node then
          label = vim.treesitter.get_node_text(node, buf, {}) .. ": " .. label
        end
      end

      local line = hint.position.line + 1
      local token = { label = label, position = hint.position.character }

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
      local pos = vim.api.nvim_win_get_cursor(0)
      local line = pos[1]
      local col = pos[2]

      local hints = vim.b.inlay_hints
      if not hints then return end

      -- If the current line has no hints, explicitly clear the echo area.
      local hint = hints[line]
      if hint == nil or hint == vim.NIL or #hint == 0 then
        vim.api.nvim_echo({}, false, {})
        return
      end

      local last = 0
      local tokens = {}
      local prefix = "["

      for _, token in ipairs(hint) do
        local at_cursor = last <= col and col < token.position
        local highlight = at_cursor and "Cursor" or "Normal"
        table.insert(tokens, { prefix, highlight })
        table.insert(tokens, { " ", "Normal" })
        table.insert(tokens, { token.label, "Type" })
        table.insert(tokens, { " ", "Normal" })

        last = token.position
        prefix = "|"
      end

      local highlight = last <= col and "Cursor" or "Normal"
      table.insert(tokens, { "]", highlight })
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
