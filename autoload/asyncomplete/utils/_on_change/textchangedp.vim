let s:callbacks = []

function! asyncomplete#utils#_on_change#textchangedp#init() abort
    if exists('##TextChangedP')
        call s:setup_if_required()
        return {
            \ 'name': 'TextChangedP',
            \ 'register': function('s:register'),
            \ 'unregister': function('s:unregister'),
        \ }
    else
        return { 'name': 'TextChangedP', 'error': 'Requires vim with TextChangedP support' }
    endif
endfunction

function! s:setup_if_required() abort
    augroup asyncomplete_utils_on_change_text_changed_p
        autocmd!
        autocmd InsertEnter * call s:on_insert_enter()
        autocmd InsertLeave * call s:on_insert_leave()
        autocmd TextChangedI * call s:on_text_changed_i()
        autocmd TextChangedP * call s:on_text_changed_p()
    augroup END
endfunction

function! s:register(cb) abort
    call add(s:callbacks , a:cb)
endfunction

function! s:unregister(obj, cb) abort
    " TODO: remove from s:callbacks
endfunction

function! s:on_insert_enter() abort
    let l:context = asyncomplete#context()
    let s:previous_context = {
        \ 'lnum': l:context['lnum'],
        \ 'col': l:context['col'],
        \ 'typed': l:context['typed'],
        \ }
endfunction

function! s:on_insert_leave() abort
    unlet! s:previous_context
endfunction

function! s:on_text_changed_i() abort
    call s:maybe_notify_on_change()
endfunction

function! s:on_text_changed_p() abort
    call s:maybe_notify_on_change()
endfunction

function! s:maybe_notify_on_change() abort
    if !exists('s:previous_context')
        return
    endif
    " We notify on_change callbacks only when the cursor position
    " has changed.
    " Unfortunatelly we need this check because in insert mode it
    " is possible to have TextChangedI triggered when the completion
    " context is not changed at all: When we close the completion
    " popup menu via <C-e> or <C-y>. If we still let on_change
    " do the completion in this case we never close the menu.
    " Vim doesn't allow programmatically changing buffer content
    " in insert mode, so by comparing the cursor's position and the
    " completion base we know whether the context has changed.
    let l:context = asyncomplete#context()
    let l:previous_context = s:previous_context
    let s:previous_context = {
        \ 'lnum': l:context['lnum'],
        \ 'col': l:context['col'],
        \ 'typed': l:context['typed'],
        \ }
    if l:previous_context !=# s:previous_context
        for l:Cb in s:callbacks
            call l:Cb()
        endfor
    endif
endfunction
