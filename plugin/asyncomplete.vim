if exists('g:asyncomplete_loaded')
    finish
endif
let g:asyncomplete_loaded = 1

if get(g:, 'asyncomplete_enable_for_all', 1)
    au BufEnter * if exists ('b:asyncomplete_enable') == 0 | call asyncomplete#enable_for_buffer() | endif
endif

let g:asyncomplete_auto_popup = get(g:, 'asyncomplete_auto_popup', 1)
let g:asyncomplete_completion_delay = get(g:, 'asyncomplete_completion_delay', 100)
let g:asyncomplete_log_file = get(g:, 'asyncomplete_log_file', '')

" imap <c-space> <Plug>(asyncomplete_force_refresh)
inoremap <silent> <expr> <Plug>(asyncomplete_force_refresh) asyncomplete#force_refresh()

if has('lua')
    lua << EOF
    asyncomplete = {}
EOF
endif
