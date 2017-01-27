asyncomplete.vim (exprimental)
==============================

Provide async autocompletion for vim8 and neovim with `timers`.
This repository is fork of [https://github.com/roxma/nvim-complete-manager](https://github.com/roxma/nvim-complete-manager)
in pure vim script with python dependency removed.

**Do not depend on this repository. This is me trying out async completion in vim so I will be pushing random things that may break**

### Installing

```viml
Plug 'prabirshrestha/asyncomplete.vim'
```

### Example

```vim
function! s:js_completor(opt, ctx) abort
    let l:col = col('.')
    let l:typed = strpart(getline('.'), 0, l:col)

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

The above sample shows synchornous completion. If you would like to make it async just call `asyncomplete#complete` whenever you have the results ready.


```vim
call timer_start(2000, {timer-> asyncomplete#complete(a:opt['name'], a:ctx, l:startcol, l:matches)})
```

### Credits
All the credit goes to the following projects
* [https://github.com/roxma/nvim-complete-manager](https://github.com/roxma/nvim-complete-manager)
* [https://github.com/maralla/completor.vim](https://github.com/maralla/completor.vim)
