# Vim client for Idris2 IDE socket

## Obsolete, abandoned in favour of [nvim-idris2](https://github.com/ShinKage/nvim-idris2)

## Requirements
- For the time being the plugin only works with Neovim.
  Supporting Vim 8 in the future isn't a problem though.
  
- This project depends on [PR #740](https://github.com/idris-lang/Idris2/pull/740)
  
- The [fd](https://github.com/sharkdp/fd) tool is required.
  Later we can relax it to any `find` like utility.

- [fzf-vim](https://github.com/junegunn/fzf.vim) is also required at the moment.

- The plugin writes to the [idris2-vim](https://github.com/edwinb/idris2-vim) response buffer
  when loading files. But you probably have it installed already.
  
- Obviously an [Idris2](https://github.com/idris-lang/Idris2) installation is a must.
  The `idris2` executable file should be in your `$PATH`.
  
## Installation
Using [vim-plug](https://github.com/junegunn/vim-plug):

`Plug 'Russoul/Idris2-Vim-Ide'`

## Usage

### Implemented features:
- Integrated Idris2 IDE server

- File loading and typechecking

- Compiler directed go-to-definition.
  Not ideal yet, but opportunities for expansions are enormous.

Default keybindings are:
```
" Go to definition by the word under the cursor.
nnoremap <silent> <Leader>K :call IdrisGoTo(expand("\<cword>"))<CR>
" Go to definition by the current visual selection.
vnoremap <silent> <Leader>K :call IdrisGoToSelection()<CR>
" Load the current file. This needs to be done before using go-to-definition.
nnoremap <silent> <Leader>L :call IdrisLoadFile()<CR>
```
You can disable them setting `g:idrisIdeDisableDefaultMaps` to `v:true` before the plugin is loaded.
