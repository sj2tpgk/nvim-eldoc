nnore Q :qa!<cr>
set notermguicolors

fu! Install(url)
    let name = substitute(substitute(a:url, "/*$", "", ""), ".*/", "", "")
    let dir = stdpath("data") . "/site/pack/" . name . "/start/"
    call mkdir(dir, "p")
    call system(["git", "-C", dir, "clone", "--depth", "1", a:url])
endfu

call Install("https://github.com/neovim/nvim-lspconfig")

lua vim.lsp.enable('pyright')

lua require("nvim-eldoc").setup()
set updatetime=700
hi EldocCur ctermfg=cyan cterm=bold
