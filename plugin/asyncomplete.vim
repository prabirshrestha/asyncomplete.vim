if exists('g:asyncomplete_loaded')
    finish
endif
let g:asyncomplete_loaded = 1

if get(g:, 'asyncomplete_enable_for_all', 1)
    au BufEnter * if exists ('b:asyncomplete_enable') == 0 | call asyncomplete#enable_for_buffer() | endif
endif

let g:asyncomplete_completion_delay = get(g:, 'asyncomplete_completion_delay', 100)
inoremap <silent> <expr> <Plug>(asyncomplete_force_refresh) (asyncomplete#menu_selected()?"\<c-y>\<c-r>=asyncomplete#force_refresh()\<CR>":"\<c-r>=asyncomplete#force_refresh()\<CR>")
" imap <c-space> <Plug>(asyncomplete_force_refresh)