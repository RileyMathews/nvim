local M = {}

---@param cmd string
---@return string?, string?
function M.exec(cmd)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "Failed to execute command"
  end

  local output = handle:read("*a")
  local success = handle:close()
  if not success then
    return nil, output
  end

  return output, nil
end

---@return string?
function M.repo_root()
  local output, err = M.exec("git rev-parse --show-toplevel")
  if err or not output then
    return nil
  end

  local root = vim.trim(output)
  if root == "" then
    return nil
  end

  return root
end

---@param args string[]
---@param opts? {repo?: string}
---@return string?, string?
function M.text(args, opts)
  opts = opts or {}
  local cmd_parts = { "gh" }
  vim.list_extend(cmd_parts, args)

  if opts.repo then
    vim.list_extend(cmd_parts, { "--repo", opts.repo })
  end

  local cmd = table.concat(cmd_parts, " ")
  return M.exec(cmd)
end

---@param args string[]
---@param opts? {repo?: string}
---@return table?, string?
function M.json(args, opts)
  local output, err = M.text(args, opts)
  if err then
    return nil, err
  end

  if not output or output == "" then
    return nil, "Empty response"
  end

  local ok, result = pcall(vim.json.decode, output)
  if not ok then
    return nil, "Failed to parse JSON"
  end

  return result, nil
end

---@param endpoint string
---@param input table?
---@param opts? {method?: string}
---@return table?, string?
function M.api(endpoint, input, opts)
  opts = opts or {}
  local method = opts.method or "POST"
  local cmd = string.format("gh api %s -X %s", endpoint, method)

  if input then
    cmd = cmd .. " --input -"
  end

  local output
  if input then
    output = vim.fn.system(cmd, vim.json.encode(input))
  else
    output = vim.fn.system(cmd)
  end

  if vim.v.shell_error ~= 0 then
    return nil, output
  end

  if not output or output == "" or not output:find("%S") then
    return {}, nil
  end

  local ok, result = pcall(vim.json.decode, output)
  if not ok then
    return nil, "Failed to parse JSON"
  end

  return result, nil
end

---@param query string
---@param variables table
---@return table?, string?
function M.graphql(query, variables)
  local result, err = M.api("graphql", {
    query = query,
    variables = variables or {},
  })
  if err then
    return nil, err
  end

  if result.errors then
    local msg = result.errors[1] and result.errors[1].message or "Unknown GraphQL error"
    return nil, msg
  end

  return result.data, nil
end

---@return {owner:string, name:string, full_name:string}?, string?
function M.get_repo_info()
  local result, err = M.json({ "repo", "view", "--json", "owner,name,nameWithOwner" })
  if err then
    return nil, "Not in a GitHub repository or gh not authenticated"
  end

  local owner = result.owner and result.owner.login or nil
  local name = result.name
  if not owner or not name then
    return nil, "Invalid repository info"
  end

  return {
    owner = owner,
    name = name,
    full_name = result.nameWithOwner or (owner .. "/" .. name),
  }, nil
end

---@return number?, string?
function M.get_current_pr_number()
  local result, err = M.json({ "pr", "view", "--json", "number" })
  if err or not result or not result.number then
    return nil, "No PR found for current branch"
  end

  return tonumber(result.number), nil
end

return M
