if exists('g:asyncomplete_loaded')
    finish
endif
let g:asyncomplete_loaded = 1

if get(g:, 'asyncomplete_enable_for_all', 1)
    augroup asyncomplete_enable
        au!
        au BufEnter * if exists('b:asyncomplete_enable') == 0 | call asyncomplete#enable_for_buffer() | endif
    augroup END
endif

let g:asyncomplete_manager = get(g:, 'asyncomplete_manager', 'asyncomplete#managers#vim#init')
let g:asyncomplete_change_manager = get(g:, 'asyncomplete_change_manager', ['asyncomplete#utils#_on_change#textchangedp#init', 'asyncomplete#utils#_on_change#timer#init'])
let g:asyncomplete_triggers = get(g:, 'asyncomplete_triggers', {'*': ['.', '>', ':'] })
let g:asyncomplete_min_chars = get(g:, 'asyncomplete_min_chars', 0)

let g:asyncomplete_auto_completeopt = get(g:, 'asyncomplete_auto_completeopt', 1)
let g:asyncomplete_auto_popup = get(g:, 'asyncomplete_auto_popup', 1)
let g:asyncomplete_popup_delay = get(g:, 'asyncomplete_popup_delay', 30)
let g:asyncomplete_log_file = get(g:, 'asyncomplete_log_file', '')
let g:asyncomplete_preprocessor = get(g:, 'asyncomplete_preprocessor', [])
let g:asyncomplete_matchfuzzy = get(g:, 'asyncomplete_matchfuzzy', exists('*matchfuzzypos'))
let g:asyncomplete_max_num_candidates = get(g:, 'asyncomplete_max_num_candidates', 50)

inoremap <silent> <expr> <Plug>(asyncomplete_force_refresh) asyncomplete#force_refresh()
