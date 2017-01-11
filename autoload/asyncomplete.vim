let s:char_inserted = v:false
let s:completions = {'words': [], 'refresh': 'always'}
let s:status = {'pos': [], 'nr': -1, 'input': '', 'ft': ''}
let s:completors = {}

function! s:completions.set(comps) abort
  let self.words = a:comps
endfunction

function! s:completions.clear() abort
  let self.words = []
endfunction

function! s:completions.empty() abort
  return empty(self.words)
endfunction

function! s:get_start_column(findstart, findbase, triggers)
    let l:line_string = getline('.')
    let l:line = line('.')
    let l:col = col('.')
    let l:start = l:col - 1
    while l:start > 0
        let l:char = l:line_string[l:start - 1]
        for l:trigger_char in a:triggers
            if l:char == l:trigger_char
                return l:start
            endif
        endfor
        let l:start -= 1
    endwhile
    return l:start
endfunction

function! asyncomplete#completefunc(findstart, findbase)
    if a:findstart
        if s:completions.empty()
            return -3
        endif
        if has_key(s:completors, s:status.ft) && has_key(s:completors[s:status.ft], 'triggers')
            return s:get_start_column(a:findstart, a:findbase, s:completors[s:status.ft].triggers)
        else
            return -3
        endif
    endif

    let l:completions = copy(s:completions)
    call s:completions.clear()
    let l:results = []
    for l:item in l:completions.words
        if l:item.word =~ '^' . a:findbase
            call add(l:results, l:item)
        endif
    endfor
    return l:results
endfunction

function! s:consistent() abort
  return s:status.nr == bufnr('') && s:status.pos == getcurpos() && s:status.ft == &ft
endfunction

function! s:trigger(items) abort
    if !s:consistent()
        call s:completions.clear()
    else
        call s:completions.set(a:items)
    endif
    if s:completions.empty() | return | endif
    setlocal completefunc=asyncomplete#completefunc
    setlocal completeopt-=longest
    setlocal completeopt+=menuone
    setlocal completeopt-=menu
    if &completeopt !~# 'noinsert\|noselect'
        setlocal completeopt+=noselect
    endif
    call feedkeys("\<C-x>\<C-u>\<C-p>", 'n')
endfunction

function! s:reset() abort
    call s:completions.clear()
endfunction

function! s:complete() abort
    call s:reset()
    if !s:consistent() | return | endif

    if has_key(s:completors, s:status.ft)
        call s:completors[s:status.ft].completor({'info': s:status, 'done': {items->s:trigger(items)}})
    endif
endfunction

function! s:skip() abort
    let l:buftype = &buftype
    let l:skip = empty(&ft) || buftype == 'nofile' || buftype == 'quickfix'
    return l:skip || !s:char_inserted
endfunction

function! s:on_text_change() abort
    if s:skip() | return | endif
    let s:char_inserted = v:false

    if exists('s:timer')
        let l:info = timer_info(s:timer)
        if !empty(l:info)
            call timer_stop(s:timer)
        endif
    endif

    let e = col('.') - 2
    let inputted = e >= 0 ? getline('.')[:e] : ''

    let s:status = {'input':inputted, 'pos': getcurpos(), 'nr': bufnr(''), 'ft': &ft}
    let s:timer = timer_start(g:asyncomplete_completion_delay, {t->s:complete()})
endfunction

function! s:on_insert_char_pre() abort
    let s:char_inserted = v:true
endfunction

function! s:set_events() abort
    augroup asyncomplete
        autocmd!
        autocmd TextChangedI * call s:on_text_change()
        autocmd InsertCharPre * call s:on_insert_char_pre()
    augroup END
endfunction

" public apis {{{

function! asyncomplete#enable() abort
    " remove this check when nvim supports lambda
    if !has('nvim')
        call s:set_events()
    endif
endfunction

function! asyncomplete#disable() abort
    autocmd! asyncomplete
endfunction

function! asyncomplete#register(filetype, triggers, completor) abort
    let s:completors[a:filetype] = { 'triggers': a:triggers, 'completor': a:completor }
endfunction

function! asyncomplete#unregister(filetype) abort
    call remove(s:completors, a:filetype)
endfunction

" }}}
