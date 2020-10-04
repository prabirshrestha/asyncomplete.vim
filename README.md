asyncomplete.vim
================

Async autocompletion for Vim 8 and Neovim with |timers|.

This is inspired by [nvim-complete-manager](https://github.com/roxma/nvim-complete-manager) but written
in pure Vim Script.

### Installing

```viml
Plug 'prabirshrestha/asyncomplete.vim'
```

#### Tab completion

```vim
inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <cr>    pumvisible() ? "\<C-y>" : "\<cr>"
```

### Force refresh completion

```vim
imap <c-space> <Plug>(asyncomplete_force_refresh)
```

### Auto popup
By default asyncomplete will automatically show the autocomplete popup menu as you start typing.
If you would like to disable the default behavior set `g:asyncomplete_auto_popup` to 0.

```vim
let g:asyncomplete_auto_popup = 0
```

You can use the above `<Plug>(asyncomplete_force_refresh)` to show the popup
or can you tab to show the autocomplete.

```vim
let g:asyncomplete_auto_popup = 0

function! s:check_back_space() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~ '\s'
endfunction

inoremap <silent><expr> <TAB>
  \ pumvisible() ? "\<C-n>" :
  \ <SID>check_back_space() ? "\<TAB>" :
  \ asyncomplete#force_refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
```

#### Preview Window

To enable preview window:

```vim
" allow modifying the completeopt variable, or it will
" be overridden all the time
let g:asyncomplete_auto_completeopt = 0

set completeopt=menuone,noinsert,noselect,preview
```

To auto close preview window when completion is done.

```vim
autocmd! CompleteDone * if pumvisible() == 0 | pclose | endif
```

### Sources

asyncomplete.vim deliberately does not contain any sources. Please use one of the following sources or create your own.

#### Language Server Protocol (LSP)
[Language Server Protocol](https://github.com/Microsoft/language-server-protocol) via [vim-lsp](https://github.com/prabirshrestha/vim-lsp) and [asyncomplete-lsp.vim](https://github.com/prabirshrestha/asyncomplete-lsp.vim)

**Please note** that vim-lsp setup for neovim requires neovim v0.2.0 or higher, since it uses lambda setup.

```vim
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/vim-lsp'
Plug 'prabirshrestha/asyncomplete-lsp.vim'

if executable('pyls')
    " pip install python-language-server
    au User lsp_setup call lsp#register_server({
        \ 'name': 'pyls',
        \ 'cmd': {server_info->['pyls']},
        \ 'allowlist': ['python'],
        \ })
endif
```

**Refer to [vim-lsp wiki](https://github.com/prabirshrestha/vim-lsp/wiki/Servers) for configuring other language servers.** Besides auto-complete language server support other features such as go to definition, find references, renaming symbols, document symbols, find workspace symbols, formatting and so on.

*in alphabetical order*

| Languages/FileType/Source     | Links                                                                                              |
|-------------------------------|----------------------------------------------------------------------------------------------------|
| Buffer                        | [asyncomplete-buffer.vim](https://github.com/prabirshrestha/asyncomplete-buffer.vim)               |
| Closure                       | [async-clj-omni](https://github.com/clojure-vim/async-clj-omni)                 |
| [Emmet][emmet-vim]            | [asyncomplete-emmet.vim](https://github.com/prabirshrestha/asyncomplete-emmet.vim)                 |
| Emoji                         | [asyncomplete-emoji.vim](https://github.com/prabirshrestha/asyncomplete-emoji.vim)                 |
| Filenames / directories       | [asyncomplete-file.vim](https://github.com/prabirshrestha/asyncomplete-file.vim)                   |
| [NeoInclude][neoinclude]      | [asyncomplete-neoinclude.vim](https://github.com/kyouryuukunn/asyncomplete-neoinclude.vim)         |
| Go                            | [asyncomplete-gocode.vim](https://github.com/prabirshrestha/asyncomplete-gocode.vim)               |
| JavaScript (Flow)             | [asyncomplete-flow.vim](https://github.com/prabirshrestha/asyncomplete-flow.vim)                   |
| [Neosnippet][neosnippet]      | [asyncomplete-neosnippet.vim](https://github.com/prabirshrestha/asyncomplete-neosnippet.vim)       |
| Omni                          | [asyncomplete-omni.vim](https://github.com/yami-beta/asyncomplete-omni.vim)                        |
| PivotalTracker stories        | [asyncomplete-pivotaltracker.vim](https://github.com/hauleth/asyncomplete-pivotaltracker.vim)      |
| Racer                         | [asyncomplete-racer.vim](https://github.com/keremc/asyncomplete-racer.vim)                         |
| [tmux complete][tmuxcomplete] | [tmux-complete.vim][tmuxcomplete]                                                                  |
| Typescript                    | [asyncomplete-tscompletejob.vim](https://github.com/prabirshrestha/asyncomplete-tscompletejob.vim) |
| [UltiSnips][ultisnips]        | [asyncomplete-ultisnips.vim](https://github.com/prabirshrestha/asyncomplete-ultisnips.vim)         |
| User (compl-function)         | [asyncomplete-user.vim](https://github.com/jsit/asyncomplete-user.vim)                             |
| Vim Syntax                    | [asyncomplete-necosyntax.vim](https://github.com/prabirshrestha/asyncomplete-necosyntax.vim)       |
| Vim tags                      | [asyncomplete-tags.vim](https://github.com/prabirshrestha/asyncomplete-tags.vim)                   |
| Vim                           | [asyncomplete-necovim.vim](https://github.com/prabirshrestha/asyncomplete-necovim.vim)             |

[emmet-vim]:    https://github.com/mattn/emmet-vim
[neosnippet]:   https://github.com/Shougo/neosnippet.vim
[neoinclude]:   https://github.com/Shougo/neoinclude.vim
[tmuxcomplete]: https://github.com/wellle/tmux-complete.vim
[ultisnips]:    https://github.com/SirVer/ultisnips

*can't find what you are looking for? write one instead an send a PR to be included here or search github topics tagged with asyncomplete at https://github.com/topics/asyncomplete.*

#### Using existing vim plugin sources

Rather than writing your own completion source from scratch you could also suggests other plugin authors to provide a async completion api that works for asyncomplete.vim or any other async autocomplete libraries without taking a dependency on asyncomplete.vim. The plugin can provide a function that takes a callback which returns the list of candidates and the startcol from where it must show the popup. Candidates can be list of words or vim's `complete-items`.

```vim
function s:completor(opt, ctx)
  call mylanguage#get_async_completions({candidates, startcol -> asyncomplete#complete(a:opt['name'], a:ctx, startcol, candidates) })
endfunction

au User asyncomplete_setup call asyncomplete#register_source({
    \ 'name': 'mylanguage',
    \ 'allowlist': ['*'],
    \ 'completor': function('s:completor'),
    \ })
```

### Example

```vim
function! s:js_completor(opt, ctx) abort
    let l:col = a:ctx['col']
    let l:typed = a:ctx['typed']

    let l:kw = matchstr(l:typed, '\v\S+$')
    let l:kwlen = len(l:kw)

    let l:startcol = l:col - l:kwlen

    let l:matches = [
        \ "do", "if", "in", "for", "let", "new", "try", "var", "case", "else", "enum", "eval", "null", "this", "true",
        \ "void", "with", "await", "break", "catch", "class", "const", "false", "super", "throw", "while", "yield",
        \ "delete", "export", "import", "public", "return", "static", "switch", "typeof", "default", "extends",
        \ "finally", "package", "private", "continue", "debugger", "function", "arguments", "interface", "protected",
        \ "implements", "instanceof"
        \ ]

    call asyncomplete#complete(a:opt['name'], a:ctx, l:startcol, l:matches)
endfunction

au User asyncomplete_setup call asyncomplete#register_source({
    \ 'name': 'javascript',
    \ 'allowlist': ['javascript'],
    \ 'completor': function('s:js_completor'),
    \ })
```

The above sample shows synchronous completion. If you would like to make it async just call `asyncomplete#complete` whenever you have the results ready.

```vim
call timer_start(2000, {timer-> asyncomplete#complete(a:opt['name'], a:ctx, l:startcol, l:matches)})
```

If you are returning incomplete results and would like to trigger completion on the next keypress pass `1` as the fifth parameter to `asyncomplete#complete`
which signifies the result is incomplete.

```vim
call asyncomplete#complete(a:opt['name'], a:ctx, l:startcol, l:matches, 1)
```

As a source author you do not have to worry about synchronization issues in case the server returns the async completion after the user has typed more
characters. asyncomplete.vim uses partial caching as well as ignores if the context changes when calling `asyncomplete#complete`.
This is one of the core reason why the original context must be passed when calling `asyncomplete#complete`.

### Credits
All the credit goes to the following projects
* [https://github.com/roxma/nvim-complete-manager](https://github.com/roxma/nvim-complete-manager)
* [https://github.com/maralla/completor.vim](https://github.com/maralla/completor.vim)

## Contributors

### Code Contributors

This project exists thanks to all the people who contribute. [[Contribute](CONTRIBUTING.md)].
<a href="https://github.com/prabirshrestha/asyncomplete.vim/graphs/contributors"><img src="https://opencollective.com/asyncomplete/contributors.svg?width=890&button=false" /></a>

### Financial Contributors

Become a financial contributor and help us sustain our community. [[Contribute](https://opencollective.com/asyncomplete/contribute)]

#### Individuals

<a href="https://opencollective.com/asyncomplete"><img src="https://opencollective.com/asyncomplete/individuals.svg?width=890"></a>

#### Organizations

Support this project with your organization. Your logo will show up here with a link to your website. [[Contribute](https://opencollective.com/asyncomplete/contribute)]

<a href="https://opencollective.com/asyncomplete/organization/0/website"><img src="https://opencollective.com/asyncomplete/organization/0/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/1/website"><img src="https://opencollective.com/asyncomplete/organization/1/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/2/website"><img src="https://opencollective.com/asyncomplete/organization/2/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/3/website"><img src="https://opencollective.com/asyncomplete/organization/3/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/4/website"><img src="https://opencollective.com/asyncomplete/organization/4/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/5/website"><img src="https://opencollective.com/asyncomplete/organization/5/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/6/website"><img src="https://opencollective.com/asyncomplete/organization/6/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/7/website"><img src="https://opencollective.com/asyncomplete/organization/7/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/8/website"><img src="https://opencollective.com/asyncomplete/organization/8/avatar.svg"></a>
<a href="https://opencollective.com/asyncomplete/organization/9/website"><img src="https://opencollective.com/asyncomplete/organization/9/avatar.svg"></a>
