vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
	callback = function(event)
		local map = function(keys, func, desc)
			vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end
		map("<leader>ca", vim.lsp.buf.code_action, "[A]ction")
		map("<leader>cr", vim.lsp.buf.rename, "[R]ename")

		local client = vim.lsp.get_client_by_id(event.data.client_id)
		if client and client.server_capabilities.documentHighlightProvider then
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				callback = vim.lsp.buf.document_highlight,
			})

			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				callback = vim.lsp.buf.clear_references,
			})
		end
		if client and client:supports_method('textDocument/inlayHint', event.buf) then
			map('<leader>ci', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
		end
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("markdown-pairs", { clear = true }),
	pattern = "markdown",
	callback = function(event)
		vim.keymap.set("i", "`", "`", { buffer = event.buf })
	end,
})
