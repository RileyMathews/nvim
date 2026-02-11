local M = {}

local function schedule_cb(cb, ...)
  if not cb then
    return
  end
  local args = { ... }
  vim.schedule(function()
    cb(unpack(args))
  end)
end

---@param cmd string[]
---@param input? string
---@param cb fun(output:string?, err:string?)
local function system_async(cmd, input, cb)
  if vim.system then
    local opts = { text = true }
    if input then
      opts.stdin = input
    end
    vim.system(cmd, opts, function(obj)
      local stdout = obj.stdout or ""
      local stderr = obj.stderr or ""
      if obj.code ~= 0 then
        schedule_cb(cb, nil, stderr ~= "" and stderr or stdout)
        return
      end
      schedule_cb(cb, stdout, nil)
    end)
    return
  end

  local stdout_chunks = {}
  local stderr_chunks = {}
  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        table.insert(stdout_chunks, table.concat(data, "\n"))
      end
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr_chunks, table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      local stdout = table.concat(stdout_chunks, "\n")
      local stderr = table.concat(stderr_chunks, "\n")
      if code ~= 0 then
        schedule_cb(cb, nil, stderr ~= "" and stderr or stdout)
        return
      end
      schedule_cb(cb, stdout, nil)
    end,
  }

  local job_id = vim.fn.jobstart(cmd, job_opts)
  if job_id <= 0 then
    schedule_cb(cb, nil, "Failed to start job")
    return
  end
  if input then
    vim.fn.chansend(job_id, input)
    vim.fn.chanclose(job_id, "stdin")
  end
end

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

---@param cmd string
---@param cb fun(output:string?, err:string?)
function M.exec_async(cmd, cb)
  system_async({ "sh", "-c", cmd }, nil, cb)
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
---@param cb fun(output:string?, err:string?)
function M.text_async(args, opts, cb)
  opts = opts or {}
  local cmd_parts = { "gh" }
  vim.list_extend(cmd_parts, args)

  if opts.repo then
    vim.list_extend(cmd_parts, { "--repo", opts.repo })
  end

  system_async(cmd_parts, nil, cb)
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

---@param args string[]
---@param opts? {repo?: string}
---@param cb fun(result:table?, err:string?)
function M.json_async(args, opts, cb)
  M.text_async(args, opts, function(output, err)
    if err then
      schedule_cb(cb, nil, err)
      return
    end

    if not output or output == "" then
      schedule_cb(cb, nil, "Empty response")
      return
    end

    local ok, result = pcall(vim.json.decode, output)
    if not ok then
      schedule_cb(cb, nil, "Failed to parse JSON")
      return
    end

    schedule_cb(cb, result, nil)
  end)
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

---@param endpoint string
---@param input table?
---@param opts? {method?: string}
---@param cb fun(result:table?, err:string?)
function M.api_async(endpoint, input, opts, cb)
  opts = opts or {}
  local method = opts.method or "POST"
  local cmd_parts = { "gh", "api", endpoint, "-X", method }
  local stdin = nil

  if input then
    vim.list_extend(cmd_parts, { "--input", "-" })
    stdin = vim.json.encode(input)
  end

  system_async(cmd_parts, stdin, function(output, err)
    if err then
      schedule_cb(cb, nil, err)
      return
    end

    if not output or output == "" or not output:find("%S") then
      schedule_cb(cb, {}, nil)
      return
    end

    local ok, result = pcall(vim.json.decode, output)
    if not ok then
      schedule_cb(cb, nil, "Failed to parse JSON")
      return
    end

    schedule_cb(cb, result, nil)
  end)
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

---@param query string
---@param variables table
---@param cb fun(data:table?, err:string?)
function M.graphql_async(query, variables, cb)
  M.api_async("graphql", {
    query = query,
    variables = variables or {},
  }, nil, function(result, err)
    if err then
      schedule_cb(cb, nil, err)
      return
    end

    if result and result.errors then
      local msg = result.errors[1] and result.errors[1].message or "Unknown GraphQL error"
      schedule_cb(cb, nil, msg)
      return
    end

    schedule_cb(cb, result and result.data or nil, nil)
  end)
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

---@param cb fun(result:{owner:string, name:string, full_name:string}?, err:string?)
function M.get_repo_info_async(cb)
  M.json_async({ "repo", "view", "--json", "owner,name,nameWithOwner" }, nil, function(result, err)
    if err then
      schedule_cb(cb, nil, "Not in a GitHub repository or gh not authenticated")
      return
    end

    local owner = result.owner and result.owner.login or nil
    local name = result.name
    if not owner or not name then
      schedule_cb(cb, nil, "Invalid repository info")
      return
    end

    schedule_cb(cb, {
      owner = owner,
      name = name,
      full_name = result.nameWithOwner or (owner .. "/" .. name),
    }, nil)
  end)
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
