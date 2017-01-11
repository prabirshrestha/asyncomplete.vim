asyncomplete.vim (exprimental)
==============================

Provide async autocompletion for vim8 with `lambda` and `timers`.
This should work in Neovim once [lambda support](https://github.com/neovim/neovim/pull/5771) is merged in master.
This repository is fork of [https://github.com/maralla/completor.vim](https://github.com/maralla/completor.vim) in pure vim script with python dependency removed.

**Do not depend on this repository. This is me trying out async completion in vim so I will be pushing random things that may break**

### Installing

```viml
Plug 'prabirshrestha/asyncomplete.vim'
```

### Example

```viml
function! s:js_completor(args)
    call timer_start(2000, {t->a:args.done([{'word': 'class'}, {'word': 'function'}, {'word': 'value'}])})
endfunction

call asyncomplete#register('javascript', ['.', ' '], function('s:js_completor'))
```

### Credits
All the credit goes to [https://github.com/maralla/completor.vim](https://github.com/maralla/completor.vim)
