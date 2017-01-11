if exists('g:asyncomplete_loaded')
    finish
endif
let g:asyncomplete_loaded = 1
let g:asyncomplete_completion_delay = get(g:, 'asyncomplete_completion_delay', 80)

augroup asyncomplete
    autocmd!
    autocmd InsertEnter * call asyncomplete#enable()
augroup END

