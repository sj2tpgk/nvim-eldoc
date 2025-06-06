-- SPDX-License-Identifier: AGPL-3.0-only

local M = {
    -- for debugging
    _lspsig_exists = false,
    _lspsig_count  = 0,
    _lspsig_last   = nil,
}

function M.setup()

    vim.cmd [[
        hi def link Eldoc    Normal
        hi def link EldocCur Identifier
        aug vimrc_lspsig
            au!
            au CursorHold,CursorHoldI,InsertEnter * lua require("nvim-eldoc").eldocUpdate()
        aug END
        " set updatetime=700 " recommended
        set noshowmode " hide "-- INSERT --" etc.
    ]]

end

function M.eldocUpdate()
    function signature_handler(err, result, ctx, config)
        -- save call count and params for debug
        M._lspsig_count = M._lspsig_count + 1
        M._lspsig_last = {
            err    = err,
            result = result,
            ctx    = ctx,
            config = config
        }

        -- erase eldoc when no signature (not at function call etc.)
        if err ~= nil or result == nil or result.signatures == nil or result.signatures[1] == nil then
            if M._lspsig_exists then
                -- only erase message when lspsig is not empty yet
                -- if already empty, we should not erase msg, otherwise other messages gets overridden
                vim.cmd("echo ''")
            end
            M._lspsig_exists = false
            return
        end

        -- highlight current param and show
        -- note: in some langs (kotlin) result.activeSignature might be -1
        local actSig = math.max(0, result.activeSignature or 0)
        local sig    = result.signatures[1+actSig]
        local sigLbl = sig.label
        local params = sig.parameters
        local actPar = sig.activeParameter or result.activeParameter
        M._lspsig_exists = true

        --  gopls sets actPar to nil when a func has optional params but you haven't added one yet; we assume you are inputting the first param
        if actPar == nil then actPar = 0 end

        if (not params) or #params == 0 or #params <= actPar then -- no params (functions with no args etc.), or active param index is more than param count. None that in this case, value of params differ among server implementations
            local chunks = { { " ", "None" }, { sigLbl, "LspSig" } }
            nvim_echo_no_hitenter(chunks, true, {})
            return
        end

        local toks = {} -- list of { type ("prefix"|"param"|"paramAct"|"delim"|"suffix"), text }
        local tok
        local function addTok(tok) table.insert(toks, tok) end

        -- analyze signatures and construct toks
        if type(params[1+actPar].label) == 'table' then -- param label is not string (e.g. pyright)

            addTok({ "prefix", sigLbl:sub(1, params[1].label[1]) })
            for i, par in ipairs(params) do
                if i >= 2 then
                    addTok({ "delim", sigLbl:sub(params[i-1].label[2]+1, par.label[1]) })
                end
                addTok({ i == 1+actPar and "paramAct" or "param", sigLbl:sub(par.label[1]+1, par.label[2]) })
            end
            addTok({ "suffix", sigLbl:sub(params[#params].label[2]+1) })

        else -- param label is string (e.g. tsserver)

            local s = 1
            local sePrev
            for i = 1, #params do
                local parLbl = params[i].label
                local ss, se = sigLbl:find(parLbl, s, true) -- find parLbl in sigLbl
                if not ss then error("param " .. parLbl .. " not found") end
                if i == 1 then
                    addTok({ "prefix", sigLbl:sub(1, ss-1) })
                else
                    addTok({ "delim", sigLbl:sub(sePrev+1, ss-1) })
                end
                addTok({ i == 1+actPar and "paramAct" or "param", parLbl })
                if i == #params then
                    addTok({ "suffix", sigLbl:sub(se+1) })
                end
                s = ss
                sePrev = se
            end

        end

        -- if sigLbl is too long, omit type signatures (from last params until sigLbl is sufficiently short)
        local maxw = (vim.fn.winwidth(0) - 12) + 5
        local sigLblLen = sigLbl:len()
        for i = #toks, 1, -1 do
            if sigLblLen < maxw then break end
            local tok = toks[i]
            local type = tok[1]
            local text = tok[2]
            if type == "param" or type == "paramAct" then
                local colonIdx = text:find(":")
                if colonIdx then -- note: colonIdx may be nil if param does not have type signature
                    tok[2] = text:sub(1, colonIdx - 1)
                    sigLblLen = sigLblLen - (text:len() - colonIdx + 1)
                end
            end
        end

        -- convert toks to chunks and echo
        local chunks = { { " ", "None" } }
        for i, tok in ipairs(toks) do
            local type = tok[1]
            if type == "prefix" or type == "delim" or type == "suffix" then
                table.insert(chunks, { tok[2], "None" })
            elseif type == "param" then
                table.insert(chunks, { tok[2], "Eldoc" })
            elseif type == "paramAct" then
                table.insert(chunks, { tok[2], "EldocCur" })
            else
                error("invalid type", type)
            end
        end

        nvim_echo_no_hitenter(chunks, true, {})

        -- exmple value of "result"
        -- {
        --     ctx = ...,
        --     result = {
        --         activeParameter = 0,
        --         activeSignature = 0,
        --         signatures = { {
        --             label = "f(a: any, b: any, c: any): any",
        --             parameters = { {
        --                 label = "a: any"
        --             }, {
        --                     label = "b: any"
        --                 }, {
        --                     label = "c: any"
        --                 } }
        --         } }
        --     }
        -- }
    end

    -- check signatureHelp provider exists
    local hasProvider = false
    for _, client in pairs(vim.lsp.get_clients({bufnr=0})) do
        if client.server_capabilities.signatureHelpProvider then
            hasProvider = true
            break
        end
    end
    if not hasProvider then
        return
    end

    -- send lsp request
    local util = require('vim.lsp.util')
    vim.lsp.buf_request(
        0,
        'textDocument/signatureHelp',
        util.make_position_params(0, "utf-8"),
        vim.lsp.with(signature_handler, {})
    )

end

function nvim_echo_no_hitenter(chunks, history, opts) -- <<<
    -- Similar to vim.api.nvim_echo but do not trigger hit-enter message
    local len = 0
    local maxw = vim.fn.winwidth(0) - 12
    local chunks2 = {}
    for i, v in ipairs(chunks) do
        table.insert(chunks2, v)
        if len + v[1]:len() > maxw then
            v[1] = v[1]:sub(1, maxw - len)
            break
        end
        len = len + v[1]:len()
    end
    vim.api.nvim_echo(chunks2, history, opts)
end -- >>>

return M

