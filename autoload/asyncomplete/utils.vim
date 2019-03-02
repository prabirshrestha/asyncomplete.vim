" Find a nearest to a `path` parent directory `directoryname` by traversing the
" filesystem upwards
function! asyncomplete#utils#find_nearest_parent_directory(path, directoryname) abort
    let l:relative_path = finddir(a:directoryname, a:path . ';')

    if !empty(l:relative_path)
        return fnamemodify(l:relative_path, ':p')
    else
        return ''
    endif
endfunction

if exists('*matchstrpos')
    function! asyncomplete#utils#matchstrpos(expr, pattern) abort
        return matchstrpos(a:expr, a:pattern)
    endfunction
else
    function! asyncomplete#utils#matchstrpos(expr, pattern) abort
        return [matchstr(a:expr, a:pattern), match(a:expr, a:pattern), matchend(a:expr, a:pattern)]
    endfunction
endif
