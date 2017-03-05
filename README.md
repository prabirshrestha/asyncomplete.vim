asyncomplete.vim (experimental)
==============================

Provide async autocompletion for vim8 and neovim with `timers`.
This repository is fork of [https://github.com/roxma/nvim-complete-manager](https://github.com/roxma/nvim-complete-manager)
in pure vim script with python dependency removed.

**Do not depend on this repository. This is me trying out async completion in vim so I will be pushing random things that may break**

### Installing

```viml
Plug 'prabirshrestha/asyncomplete.vim'
```

#### Tab completion

```vim
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <cr> pumvisible() ? "\<C-y>\<cr>" : "\<cr>"
```

### Force refresh completion

```vim
imap <c-space> <Plug>(asyncomplete_force_refresh)
```

#### Preview Window

To disable preview window:

```vim
set completeop-=preview
```

To enable preview window:

```vim
set completeopt+=preview
```

To auto close preview window when completion is done.

```vim
autocmd! CompleteDone * if pumvisible() == 0 | pclose | endif
```

### Sources

asyncomplete.vim deliberately does not contain any sources. Please use one of the following sources or create your own.

* Buffer via [asyncomplete-buffer.vim](https://github.com/prabirshrestha/asyncomplete-buffer.vim)
* Go via [asyncomplete-gocode.vim](https://github.com/prabirshrestha/asyncomplete-gocode.vim)
* [Neosnippet](https://github.com/Shougo/neosnippet.vim) via [asyncomplete-neosnippet.vim](https://github.com/prabirshrestha/asyncomplete-neosnippet.vim)
* [UltiSnips](https://github.com/SirVer/ultisnips) via [asyncomplete-ultisnips.vim](https://github.com/prabirshrestha/asyncomplete-ultisnips.vim)
* Typescript via [asyncomplete-tscompletejob.vim](https://github.com/prabirshrestha/asyncomplete-tscompletejob.vim)
* *can't find what you are looking for? write one instead an send a PR to be included here*

### Example

```vim
function! s:js_completor(opt, ctx) abort
    let l:col = a:ctx['col']
    let l:typed = a:ctx['typed']

    let l:kw = matchstr(l:typed, '\v\S+$')
    let l:kwlen = len(l:kw)

    if l:kwlen < 1
        return
    endif

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

call asyncomplete#register_source({
    \ 'name': 'javascript',
    \ 'whitelist': ['javascript'],
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
