" Find a nearest to a `filename` directory `directoryname` by traversing the
" filesystem upwards
function! asyncomplete#utils#find_nearest_directory(filename, directoryname) abort
    let l:relative_path = finddir(a:directoryname, a:filename . ';')

    if !empty(l:relative_path)
        return fnamemodify(l:relative_path, ':p')
    else
        return ''
    endif
endfunction
