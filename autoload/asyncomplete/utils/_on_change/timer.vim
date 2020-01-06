let s:callbacks = []

let s:change_timer = -1
let s:last_tick = []

function! asyncomplete#utils#_on_change#timer#init() abort
    call s:setup_if_required()
    return {
        \ 'name': 'timer',
        \ 'register': function('s:register'),
        \ 'unregister': function('s:unregister'),
    \ }
endfunction

function! s:setup_if_required() abort
    augroup asyncomplete_utils_on_change_timer
        autocmd!
        autocmd InsertEnter * call s:on_insert_enter()
        autocmd InsertLeave * call s:on_insert_leave()
        autocmd TextChangedI * call s:on_text_changed_i()
    augroup END
endfunction

function! s:register(cb) abort
    call add(s:callbacks , a:cb)
endfunction

function! s:unregister(obj, cb) abort
    " TODO: remove from s:callbacks
endfunction

function! s:on_insert_enter() abort
    call s:change_tick_start(v:true)
endfunction

function! s:on_insert_leave() abort
    call s:change_tick_stop()
endfunction

function! s:on_text_changed_i() abort
    call s:check_changes()
endfunction

function! s:change_tick_start(...) abort
    let l:force = get(a:000, 0, v:false)
    if !exists('s:change_timer')
        if l:force
            let s:last_tick = [-1]
        else
            let s:last_tick = s:change_tick()
        endif
        " changes every 30ms, which is 0.03s, it should be fast enough
        let s:change_timer = timer_start(30, function('s:check_changes'), { 'repeat': -1 })
    endif
endfunction

function! s:change_tick_stop() abort
    if exists('s:change_timer')
        call timer_stop(s:change_timer)
        unlet s:change_timer
        let s:last_tick = []
    endif
endfunction

function! s:check_changes(...) abort
    let l:tick = s:change_tick()
    if l:tick != s:last_tick
        let s:last_tick = l:tick
        call s:maybe_notify_on_change()
    endif
endfunction

function! s:maybe_notify_on_change() abort
    for l:Cb in s:callbacks
        call l:Cb()
    endfor
endfunction

function! s:change_tick() abort
    return [b:changedtick]
endfunction
