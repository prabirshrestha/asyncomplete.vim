function! asyncomplete#log(...) abort
    if !empty(g:asyncomplete_log_file)
        call writefile([json_encode(a:000)], g:asyncomplete_log_file, 'a')
    endif
endfunction

" do nothing, place it here only to avoid the message
augroup asyncomplete_silence_messages
    au!
    autocmd User asyncomplete_setup silent
augroup END

if !has('timers')
    echohl ErrorMsg
    echomsg 'Vim/Neovim compiled with timers required for asyncomplete.vim.'
    echohl NONE
    if has('nvim')
        call asyncomplete#log('neovim compiled with timers required.')
    else
        call asyncomplete#log('vim compiled with timers required.')
    endif
    " Clear augroup so this message is only displayed once.
    au! asyncomplete_enable *
    finish
endif

let s:already_setup = 0
let s:sources = {}
let s:matches = {} " { server_name: { incomplete: 1, startcol: 0, items: [], refresh: 0, status: 'idle|pending|success|failure', ctx: ctx } }
let s:has_complete_info = exists('*complete_info')

function! s:setup_if_required() abort
    if !s:already_setup
        " register asyncomplete change manager
        for l:change_manager in g:asyncomplete_change_manager
            call asyncomplete#log('core', 'initializing asyncomplete change manager', l:change_manager)
            if type(l:change_manager) == type('')
                execute 'let s:on_change_manager = function("'. l:change_manager  .'")()'
            else
                let s:on_change_manager = l:change_manager()
            endif
            if has_key(s:on_change_manager, 'error')
                call asyncomplete#log('core', 'initializing asyncomplete change manager failed', s:on_change_manager['name'], s:on_change_manager['error'])
            else
                call s:on_change_manager.register(function('s:on_change'))
                call asyncomplete#log('core', 'initializing asyncomplete change manager complete', s:on_change_manager['name'])
                break
            endif
        endfor

        augroup asyncomplete
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call s:on_insert_leave()
        augroup END

        doautocmd <nomodeline> User asyncomplete_setup
        let s:already_setup = 1
    endif
endfunction

function! asyncomplete#enable_for_buffer() abort
    call s:setup_if_required()
    let b:asyncomplete_enable = 1
endfunction

function! asyncomplete#disable_for_buffer() abort
    let b:asyncomplete_enable = 0
endfunction

function! asyncomplete#get_source_names() abort
    return keys(s:sources)
endfunction

function! asyncomplete#get_source_info(source_name) abort
    return s:sources[a:source_name]
endfunction

function! asyncomplete#register_source(info) abort
    if has_key(s:sources, a:info['name'])
        call asyncomplete#log('core', 'duplicate asyncomplete#register_source', a:info['name'])
        return -1
    else
        let s:sources[a:info['name']] = a:info
        if has_key(a:info, 'events') && has_key(a:info, 'on_event')
            execute 'augroup asyncomplete_source_event_' . a:info['name']
            for l:event in a:info['events']
                let l:exec =  'if get(b:,"asyncomplete_enable",0) | call s:notify_event_to_source("' . a:info['name'] . '", "'.l:event.'",asyncomplete#context()) | endif'
                if type(l:event) == type('')
                    execute 'au ' . l:event . ' * ' . l:exec
                elseif type(l:event) == type([])
                    execute 'au ' . join(l:event,' ') .' ' .  l:exec
                endif
            endfor
            execute 'augroup end'
        endif

        if exists('b:asyncomplete_active_sources')
          unlet b:asyncomplete_active_sources
          call s:get_active_sources_for_buffer()
        endif

        if exists('b:asyncomplete_triggers')
          unlet b:asyncomplete_triggers
          call s:update_trigger_characters()
        endif

        return 1
    endif
endfunction

function! asyncomplete#unregister_source(info_or_server_name) abort
    if type(a:info_or_server_name) == type({})
        let l:server_name = a:info_or_server_name['name']
    else
        let l:server_name = a:info_or_server_name
    endif
    if has_key(s:sources, l:server_name)
        let l:server = s:sources[l:server_name]
        if has_key(l:server, 'unregister')
            call l:server.unregister()
        endif
        unlet s:sources[l:server_name]
        return 1
    else
        return -1
    endif
endfunction

function! asyncomplete#context() abort
    let l:ret = {'bufnr':bufnr('%'), 'curpos':getcurpos(), 'changedtick':b:changedtick}
    let l:ret['lnum'] = l:ret['curpos'][1]
    let l:ret['col'] = l:ret['curpos'][2]
    let l:ret['filetype'] = &filetype
    let l:ret['filepath'] = expand('%:p')
    let l:ret['typed'] = strpart(getline(l:ret['lnum']),0,l:ret['col']-1)
    return l:ret
endfunction

function! s:on_insert_enter() abort
    call s:get_active_sources_for_buffer() " call to cache
    call s:update_trigger_characters()
endfunction

function! s:on_insert_leave() abort
    let s:matches = {}
    if exists('s:update_pum_timer')
        call timer_stop(s:update_pum_timer)
        unlet s:update_pum_timer
    endif
endfunction

function! s:get_active_sources_for_buffer() abort
    if exists('b:asyncomplete_active_sources')
        " active sources were cached for buffer
        return b:asyncomplete_active_sources
    endif

    call asyncomplete#log('core', 'computing active sources for buffer', bufnr('%'))
    let b:asyncomplete_active_sources = []
    for [l:name, l:info] in items(s:sources)
        let l:blocked = 0

        if has_key(l:info, 'blocklist')
            let l:blocklistkey = 'blocklist'
        else
            let l:blocklistkey = 'blacklist'
        endif
        if has_key(l:info, l:blocklistkey)
            for l:filetype in l:info[l:blocklistkey]
                if l:filetype == &filetype || l:filetype is# '*'
                    let l:blocked = 1
                    break
                endif
            endfor
        endif

        if l:blocked
            continue
        endif

        if has_key(l:info, 'allowlist')
            let l:allowlistkey = 'allowlist'
        else
            let l:allowlistkey = 'whitelist'
        endif
        if has_key(l:info, l:allowlistkey)
            for l:filetype in l:info[l:allowlistkey]
                if l:filetype == &filetype || l:filetype is# '*'
                    let b:asyncomplete_active_sources += [l:name]
                    break
                endif
            endfor
        endif
    endfor

    call asyncomplete#log('core', 'active source for buffer', bufnr('%'), b:asyncomplete_active_sources)

    return b:asyncomplete_active_sources
endfunction

function! s:update_trigger_characters() abort
    if exists('b:asyncomplete_triggers')
        " triggers were cached for buffer
        return b:asyncomplete_triggers
    endif
    let b:asyncomplete_triggers = {} " { char: { 'sourcea': 1, 'sourceb': 2 } }

    for l:source_name in s:get_active_sources_for_buffer()
        let l:source_info = s:sources[l:source_name]
        if has_key(l:source_info, 'triggers') && has_key(l:source_info['triggers'], &filetype)
            let l:triggers = l:source_info['triggers'][&filetype]
        elseif has_key(l:source_info, 'triggers') && has_key(l:source_info['triggers'], '*')
            let l:triggers = l:source_info['triggers']['*']
        elseif has_key(g:asyncomplete_triggers, &filetype)
            let l:triggers = g:asyncomplete_triggers[&filetype]
        elseif has_key(g:asyncomplete_triggers, '*')
            let l:triggers = g:asyncomplete_triggers['*']
        else
            let l:triggers = []
        endif

        for l:trigger in l:triggers
            let l:last_char = l:trigger[len(l:trigger) -1]
            if !has_key(b:asyncomplete_triggers, l:last_char)
                let b:asyncomplete_triggers[l:last_char] = {}
            endif
            if !has_key(b:asyncomplete_triggers[l:last_char], l:source_name)
                let b:asyncomplete_triggers[l:last_char][l:source_name] = []
            endif
            call add(b:asyncomplete_triggers[l:last_char][l:source_name], l:trigger)
        endfor
    endfor
    call asyncomplete#log('core', 'trigger characters for buffer', bufnr('%'), b:asyncomplete_triggers)
endfunction

function! s:should_skip() abort
    if mode() isnot# 'i' || !get(b:, 'asyncomplete_enable', 0)
        return 1
    else
        return 0
    endif
endfunction

function! asyncomplete#close_popup() abort
  return pumvisible() ? "\<C-y>" : ''
endfunction

function! asyncomplete#cancel_popup() abort
  return pumvisible() ? "\<C-e>" : ''
endfunction

function! s:get_min_chars(source_name) abort
  if exists('b:asyncomplete_min_chars')
    return b:asyncomplete_min_chars
  elseif has_key(s:sources, a:source_name)
    return get(s:sources[a:source_name], 'min_chars', g:asyncomplete_min_chars)
  endif
  return g:asyncomplete_min_chars
endfunction

function! s:on_change() abort
    if s:should_skip() | return | endif

    if !g:asyncomplete_auto_popup
        return
    endif

    let l:ctx = asyncomplete#context()
    let l:last_char = l:ctx['typed'][l:ctx['col'] - 2] " col is 1-indexed, but str 0-indexed
    let l:triggered_sources = get(b:asyncomplete_triggers, l:last_char, {})
    let l:refresh_pattern = get(b:, 'asyncomplete_refresh_pattern', g:asyncomplete_refresh_pattern)
    let [l:_, l:startidx, l:endidx] = asyncomplete#utils#matchstrpos(l:ctx['typed'], l:refresh_pattern)

    for l:source_name in b:asyncomplete_active_sources
        " match sources based on the last character if it is a trigger character
        " TODO: also check for multiple chars instead of just last chars for
        " languages such as cpp which uses -> and ::
        if has_key(triggered_sources, l:source_name)
            let l:startcol = l:ctx['col']
        elseif l:startidx > -1 && l:endidx - l:startidx >= s:get_min_chars(l:source_name)
            let l:startcol = l:startidx + 1 " col is 1-indexed, but str 0-indexed
        endif
        " here we use the existence of `l:startcol` to determine whether to
        " use this completion source. If `l:startcol` exists, we use the
        " source. If it does not exist, it means that we cannot get a
        " meaningful starting point for the current source, and this implies
        " that we cannot use this source for completion. Therefore, we remove
        " the matches from the source.
        if exists('l:startcol')
            if !has_key(s:matches, l:source_name) || s:matches[l:source_name]['ctx']['lnum'] !=# l:ctx['lnum'] || s:matches[l:source_name]['startcol'] !=# l:startcol
                let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'idle', 'items': [], 'refresh': 0, 'ctx': l:ctx }
            endif
        else
            if has_key(s:matches, l:source_name)
                unlet s:matches[l:source_name]
            endif
        endif
    endfor

    call s:trigger(l:ctx)
    call s:update_pum()
endfunction

function! s:trigger(ctx) abort
    " send cancellation request if supported
    for [l:source_name, l:matches] in items(s:matches)
        call asyncomplete#log('core', 's:trigger', l:matches)
        if l:matches['refresh'] || l:matches['status'] ==# 'idle' || l:matches['status'] ==# 'failure'
            let l:matches['status'] = 'pending'
            try
                " TODO: check for min chars
                call asyncomplete#log('core', 's:trigger.completor()', l:source_name, s:matches[l:source_name], a:ctx)
                call s:sources[l:source_name].completor(s:sources[l:source_name], a:ctx)
            catch
                let l:matches['status'] = 'failure'
                call asyncomplete#log('core', 's:trigger', 'error', v:exception)
                continue
            endtry
        endif
    endfor
endfunction

function! asyncomplete#complete(name, ctx, startcol, items, ...) abort
    let l:refresh = a:0 > 0 ? a:1 : 0
    let l:ctx = asyncomplete#context()
    if !has_key(s:matches, a:name) || l:ctx['lnum'] != a:ctx['lnum'] " TODO: handle more context changes
        call asyncomplete#log('core', 'asyncomplete#log', 'ignoring due to context chnages', a:name, a:ctx, a:startcol, l:refresh, a:items)
        call s:update_pum()
        return
    endif

    call asyncomplete#log('asyncomplete#complete', a:name, a:ctx, a:startcol, l:refresh, a:items)

    let l:matches = s:matches[a:name]
    let l:matches['items'] = s:normalize_items(a:items)
    let l:matches['refresh'] = l:refresh
    let l:matches['startcol'] = a:startcol
    let l:matches['status'] = 'success'

    call s:update_pum()
endfunction

function! s:normalize_items(items) abort
    if len(a:items) > 0 && type(a:items[0]) ==# type('')
        let l:items = []
        for l:item in a:items
            let l:items += [{'word': l:item }]
        endfor
        return l:items
    else
        return a:items
    endif
endfunction

function! asyncomplete#force_refresh() abort
    return asyncomplete#menu_selected() ? "\<c-y>\<c-r>=asyncomplete#_force_refresh()\<CR>" : "\<c-r>=asyncomplete#_force_refresh()\<CR>"
endfunction

function! asyncomplete#_force_refresh() abort
    if s:should_skip() | return | endif

    let l:ctx = asyncomplete#context()
    let l:startcol = l:ctx['col']
    let l:last_char = l:ctx['typed'][l:startcol - 2]

    " loop left and find the start of the word or trigger chars and set it as the startcol for the source instead of refresh_pattern
    let l:refresh_pattern = get(b:, 'asyncomplete_refresh_pattern', '\(\k\+$\)')
    let [l:_, l:startidx, l:endidx] = asyncomplete#utils#matchstrpos(l:ctx['typed'], l:refresh_pattern)
    " When no word here, startcol is current col
    let l:startcol = l:startidx == -1 ? col('.') : l:startidx + 1

    let s:matches = {}

    for l:source_name in b:asyncomplete_active_sources
        let s:matches[l:source_name] = { 'startcol': l:startcol, 'status': 'idle', 'items': [], 'refresh': 0, 'ctx': l:ctx }
    endfor

    call s:trigger(l:ctx)
    call s:update_pum()
    return ''
endfunction

function! s:update_pum() abort
    if exists('s:update_pum_timer')
        call timer_stop(s:update_pum_timer)
        unlet s:update_pum_timer
    endif
    call asyncomplete#log('core', 's:update_pum')
    let s:update_pum_timer = timer_start(g:asyncomplete_popup_delay, function('s:recompute_pum'))
endfunction

function! s:recompute_pum(...) abort
    if s:should_skip() | return | endif

    " TODO: add support for remote recomputation of complete items,
    " Ex: heavy computation such as fuzzy search can happen in a python thread

    call asyncomplete#log('core', 's:recompute_pum')

    if asyncomplete#menu_selected()
        call asyncomplete#log('core', 's:recomputed_pum', 'ignorning refresh pum due to menu selection')
        return
    endif

    let l:ctx = asyncomplete#context()

    let l:startcols = []
    let l:matches_to_filter = {}

    for [l:source_name, l:match] in items(s:matches)
        let l:startcol = l:match['startcol']
        let l:startcols += [l:startcol]
        let l:curitems = l:match['items']

        if l:startcol > l:ctx['col']
            call asyncomplete#log('core', 's:recompute_pum', 'ignoring due to wrong start col', l:startcol, l:ctx['col'])
            continue
        else
            let l:matches_to_filter[l:source_name] = l:match
        endif
    endfor

    let l:startcol = min(l:startcols)
    let l:base = l:ctx['typed'][l:startcol - 1:] " col is 1-indexed, but str 0-indexed

    let l:filter_ctx = extend({
        \ 'base': l:base,
        \ 'startcol': l:startcol,
        \ }, l:ctx)

    let l:mode = s:has_complete_info ? complete_info(['mode'])['mode'] : 'unknown'
    if l:mode ==# '' || l:mode ==# 'eval' || l:mode ==# 'unknown'
        let l:Preprocessor = empty(g:asyncomplete_preprocessor) ? function('s:default_preprocessor') : g:asyncomplete_preprocessor[0]
        call l:Preprocessor(l:filter_ctx, l:matches_to_filter)
    endif
endfunction

let s:pair = {
\  '"':  '"',
\  '''':  '''',
\}

function! s:default_preprocessor(options, matches) abort
    let l:items = []
    let l:startcols = []
    for [l:source_name, l:matches] in items(a:matches)
        let l:startcol = l:matches['startcol']
        let l:base = a:options['typed'][l:startcol - 1:]
        if has_key(s:sources[l:source_name], 'filter')
            let [l:items, l:startcols] = s:sources[l:source_name].filter(l:matches, l:startcol, l:base)
        else
            for l:item in l:matches['items']
                if stridx(l:item['word'], l:base) == 0
                    " Strip pair characters. If pre-typed text is '"', candidates
                    " should have '"' suffix.
                    if has_key(s:pair, l:base[0])
                        let [l:lhs, l:rhs, l:str] = [l:base[0], s:pair[l:base[0]], l:item['word']]
                        if len(l:str) > 1 && l:str[0] ==# l:lhs && l:str[-1:] ==# l:rhs
                            let l:before = l:item['word']
                            let l:item['word'] = l:str[:-2]
                        endif
                    endif
                    let l:startcols += [l:startcol]
                    call add(l:items, l:item)
                endif
            endfor
        endif
    endfor

    let a:options['startcol'] = min(l:startcols)

    call asyncomplete#preprocess_complete(a:options, l:items)
endfunction

function! asyncomplete#preprocess_complete(ctx, items)
    " TODO: handle cases where this is called asynchronsouly. Currently not supported
    if s:should_skip() | return | endif

    call asyncomplete#log('core', 'asyncomplete#preprocess_complete')

    if asyncomplete#menu_selected()
        call asyncomplete#log('core', 'asyncomplete#preprocess_complete', 'ignorning pum update due to menu selection')
        return
    endif

    if (g:asyncomplete_auto_completeopt == 1)
        setl completeopt=menuone,noinsert,noselect
    endif

    call asyncomplete#log('core', 'asyncomplete#preprocess_complete calling complete()', a:ctx['startcol'], a:items)
    call complete(a:ctx['startcol'], a:items)
endfunction

function! asyncomplete#menu_selected() abort
    " when the popup menu is visible, v:completed_item will be the
    " current_selected item
    " if v:completed_item is empty, no item is selected
    return pumvisible() && !empty(v:completed_item)
endfunction

function! s:notify_event_to_source(name, event, ctx) abort
    try
        if has_key(s:sources, a:name)
            call s:sources[a:name].on_event(s:sources[a:name], a:ctx, a:event)
        endif
    catch
        call asyncomplete#log('core', 's:notify_event_to_source', 'error', v:exception)
        return
    endtry
endfunction
