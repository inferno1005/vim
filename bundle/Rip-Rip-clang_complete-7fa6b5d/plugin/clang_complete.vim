"
" File: clang_complete.vim
" Author: Xavier Deguillard <deguilx@gmail.com>
"
" Description: Use of clang to complete in C/C++.
"
" Configuration: Each project can have a .clang_complete at his root,
"                containing the compiler options. This is useful if
"                you're using some non-standard include paths.
"                For simplicity, please don't put relative and
"                absolute include path on the same line. It is not
"                currently correctly handled.
"
" Options:
"  - g:clang_complete_auto:
"       if equal to 1, automatically complete after ->, ., ::
"       Default: 1
"
"  - g:clang_complete_copen:
"       if equal to 1, open quickfix window on error.
"       Default: 0
"
"  - g:clang_hl_errors:
"       if equal to 1, it will highlight the warnings and errors the
"       same way clang does it.
"       Default: 1
"
"  - g:clang_periodic_quickfix:
"       if equal to 1, it will periodically update the quickfix window
"       Note: You could use the g:ClangUpdateQuickFix() to do the same
"             with a mapping.
"       Default: 0
"
"  - g:clang_snippets:
"       if equal to 1, it will do some snippets magic after having selected
"       something to complete.
"       Default: 0
"
"  - g:clang_snippets_engine:
"       the snippets engine (clang_complete, snipmate, ultisnips... see the
"       snippets subdirectory).
"       Default: 'clang_complete'
"
"  - g:clang_exec:
"       Name or path of clang executable.
"       Note: Use this if clang has a non-standard name, or isn't in the
"       path.
"       Default: 'clang'
"
"  - g:clang_user_options:
"       Option added at the end of clang command. Useful if you want to
"       filter the result, or if you want to ignore the error code
"       returned by clang: on error, the completion is not shown.
"       Default: ''
"       Example: '|| exit 0' (it will discard clang return value)
"
"  - g:clang_use_library:
"       Instead of calling the clang/clang++ tool use libclang directly. This
"       should improve the performance, but is still experimental.
"       Don't forget to set g:clang_library_path.
"       Default: has('python') && exists('g:clang_library_path')
"
"  - g:clang_library_path:
"       If libclang.[dll/so/dylib] is not in your library search path, set
"       this to the absolute path where libclang is available.
"       Default: variable doesn't exists
"
"  - g:clang_sort_algo:
"       How results are sorted (alpha, priority).
"       Currently only works with libclang.
"       Default: 'priority'
"
"  - g:clang_debug:
"       Output debugging informations, like timeing output of completion.
"       Default: 0
"
" Todo: - Fix bugs
"       - Parse fix-its and do something useful with it.
"       - -code-completion-macros -code-completion-patterns
"

au FileType c,cpp,objc,objcpp call s:ClangCompleteInit()

let b:clang_parameters = ''
let b:clang_user_options = ''
let b:my_changedtick = 0
let b:clang_type_complete = 0

" Store plugin path, as this is available only when sourcing the file,
" not during a function call.
let s:plugin_path = escape(expand('<sfile>:p:h'), '\')

function! s:ClangCompleteInit()
  let l:local_conf = findfile('.clang_complete', '.;')
  let b:clang_user_options = ''
  if l:local_conf != '' && filereadable(l:local_conf)
    let l:opts = readfile(l:local_conf)
    for l:opt in l:opts
      " Better handling of absolute path
      " I don't know if those pattern will work on windows
      " platform
      if matchstr(l:opt, '\C-I\s*/') != ''
        let l:opt = substitute(l:opt, '\C-I\s*\(/\%(\w\|\\\s\)*\)',
              \ '-I' . '\1', 'g')
      else
        let l:opt = substitute(l:opt, '\C-I\s*\(\%(\w\|\\\s\)*\)',
              \ '-I' . l:local_conf[:-16] . '\1', 'g')
      endif
      let b:clang_user_options .= ' ' . l:opt
    endfor
  endif

  if !exists('g:clang_complete_auto')
    let g:clang_complete_auto = 1
  endif

  if !exists('g:clang_complete_copen')
    let g:clang_complete_copen = 0
  endif

  if !exists('g:clang_hl_errors')
    let g:clang_hl_errors = 1
  endif

  if !exists('g:clang_periodic_quickfix')
    let g:clang_periodic_quickfix = 0
  endif

  if !exists('g:clang_snippets')
    let g:clang_snippets = 0
  endif

  if !exists('g:clang_snippets_engine')
    let g:clang_snippets_engine = 'clang_complete'
  endif

  if !exists('g:clang_exec')
    let g:clang_exec = 'clang'
  endif

  if !exists('g:clang_user_options')
    let g:clang_user_options = ''
  endif

  " Only use libclang if the user clearly show intent to do so for now
  if !exists('g:clang_use_library')
    let g:clang_use_library = (has('python') && exists('g:clang_library_path'))
  endif

  if !exists('g:clang_debug')
    let g:clang_debug = 0
  endif

  if !exists('g:clang_sort_algo')
    let g:clang_sort_algo = 'priority'
  endif

  inoremap <expr> <buffer> <C-X><C-U> LaunchCompletion()
  inoremap <expr> <buffer> . CompleteDot()
  inoremap <expr> <buffer> > CompleteArrow()
  inoremap <expr> <buffer> : CompleteColon()

  if g:clang_snippets == 1
    try
      call eval('snippets#' . g:clang_snippets_engine . '#init()')
    catch /^Vim\%((\a\+)\)\=:E117/
      echoe 'Snippets engine ' . g:clang_snippets_engine . ' not found.'
      let g:clang_snippets = 0
    endtry
  endif

  " Disable every autocmd that could have been set.
  augroup ClangComplete
    autocmd!
  augroup end

  let b:should_overload = 0
  let b:my_changedtick = b:changedtick
  let b:clang_parameters = '-x c'
  let b:clang_type_complete = 0

  if &filetype == 'objc'
    let b:clang_parameters = '-x objective-c'
  endif

  if &filetype == 'cpp' || &filetype == 'objcpp'
    let b:clang_parameters .= '++'
  endif

  if expand('%:e') =~ 'h*'
    let b:clang_parameters .= '-header'
  endif

  setlocal completefunc=ClangComplete
  setlocal omnifunc=ClangComplete

  if g:clang_periodic_quickfix == 1
    augroup ClangComplete
      au CursorHold,CursorHoldI <buffer> call s:DoPeriodicQuickFix()
    augroup end
  endif

  " Load the python bindings of libclang
  if g:clang_use_library == 1
    if has('python')
      exe s:initClangCompletePython()
    else
      echoe 'clang_complete: No python support available.'
      echoe 'Cannot use clang library, using executable'
      echoe 'Compile vim with python support to use libclang'
      let g:clang_use_library = 0
      return
    endif
  endif
endfunction

function! s:initClangCompletePython()
  python import sys

  if exists('g:clang_library_path')
    " Load the library from the given library path.
    exe 'python sys.argv = ["' . escape(g:clang_library_path, '\') . '"]'
  else
    " By setting argv[0] to '' force the python bindings to load the library
    " from the normal system search path.
    python sys.argv[0] = ''
  endif

  exe 'python sys.path = ["' . s:plugin_path . '"] + sys.path'
  exe 'pyfile ' . s:plugin_path . '/libclang.py'
  python initClangComplete()
endfunction

function! s:GetKind(proto)
  if a:proto == ''
    return 't'
  endif
  let l:ret = match(a:proto, '^\[#')
  let l:params = match(a:proto, '(')
  if l:ret == -1 && l:params == -1
    return 't'
  endif
  if l:ret != -1 && l:params == -1
    return 'v'
  endif
  if l:params != -1
    return 'f'
  endif
  return 'm'
endfunction

function! s:CallClangBinaryForDiagnostics(tempfile)
  let l:escaped_tempfile = shellescape(a:tempfile)
  let l:buf = getline(1, '$')
  try
    call writefile(l:buf, a:tempfile)
  catch /^Vim\%((\a\+)\)\=:E482/
    return
  endtry

  let l:command = g:clang_exec . ' -cc1 -fsyntax-only'
        \ . ' -fno-caret-diagnostics -fdiagnostics-print-source-range-info'
        \ . ' ' . l:escaped_tempfile
        \ . ' ' . b:clang_parameters . ' ' . b:clang_user_options . ' ' . g:clang_user_options

  let l:clang_output = split(system(l:command), "\n")
  call delete(a:tempfile)
  return l:clang_output
endfunction

function! s:CallClangForDiagnostics(tempfile)
  if g:clang_use_library == 1
    python updateCurrentDiagnostics()
  else
    return s:CallClangBinaryForDiagnostics(a:tempfile)
  endif
endfunction

function! s:DoPeriodicQuickFix()
  " Don't do any superfluous reparsing.
  if b:my_changedtick == b:changedtick
    return
  endif
  let b:my_changedtick = b:changedtick

  " Create tempfile name for clang/clang++ executable mode
  let b:my_changedtick = b:changedtick
  let l:tempfile = expand('%:p:h') . '/' . localtime() . expand('%:t')

  let l:clang_output = s:CallClangForDiagnostics(l:tempfile)

  call s:ClangQuickFix(l:clang_output, l:tempfile)
endfunction

function! s:ClangQuickFix(clang_output, tempfname)
  " Clear the bad spell, the user may have corrected them.
  syntax clear SpellBad
  syntax clear SpellLocal

  if g:clang_use_library == 0
    let l:list = s:ClangUpdateQuickFix(a:clang_output, a:tempfname)
  else
    python vim.command('let l:list = ' + str(getCurrentQuickFixList()))
    python highlightCurrentDiagnostics()
  endif

  if g:clang_complete_copen == 1
    " We should get back to the original buffer
    let l:bufnr = bufnr('%')

    " Workaround:
    " http://vim.1045645.n5.nabble.com/setqflist-inconsistency-td1211423.html
    if l:list == []
      cclose
    else
      copen
    endif

    let l:winbufnr = bufwinnr(l:bufnr)
    exe l:winbufnr . 'wincmd w'
  endif
  call setqflist(l:list)
  doautocmd QuickFixCmdPost make
endfunction

function! s:ClangUpdateQuickFix(clang_output, tempfname)
  let l:list = []
  for l:line in a:clang_output
    let l:erridx = match(l:line, '\%(error\|warning\): ')
    if l:erridx == -1
      " Error are always at the beginning.
      if l:line[:11] == 'COMPLETION: ' || l:line[:9] == 'OVERLOAD: '
        break
      endif
      continue
    endif
    let l:pattern = '^\(.*\):\(\d*\):\(\d*\):\(\%({\d\+:\d\+-\d\+:\d\+}\)*\)'
    let l:tmp = matchstr(l:line, l:pattern)
    let l:fname = substitute(l:tmp, l:pattern, '\1', '')
    if l:fname == a:tempfname
      let l:fname = '%'
    endif
    let l:bufnr = bufnr(l:fname, 1)
    let l:lnum = substitute(l:tmp, l:pattern, '\2', '')
    let l:col = substitute(l:tmp, l:pattern, '\3', '')
    let l:errors = substitute(l:tmp, l:pattern, '\4', '')
    if l:line[l:erridx] == 'e'
      let l:text = l:line[l:erridx + 7:]
      let l:type = 'E'
      let l:hlgroup = ' SpellBad '
    else
      let l:text = l:line[l:erridx + 9:]
      let l:type = 'W'
      let l:hlgroup = ' SpellLocal '
    endif
    let l:item = {
          \ 'bufnr': l:bufnr,
          \ 'lnum': l:lnum,
          \ 'col': l:col,
          \ 'text': l:text,
          \ 'type': l:type }
    let l:list = add(l:list, l:item)

    if g:clang_hl_errors == 0 || l:fname != '%'
      continue
    endif

    " Highlighting the ^
    let l:pat = '/\%' . l:lnum . 'l' . '\%' . l:col . 'c./'
    exe 'syntax match' . l:hlgroup . l:pat

    if l:errors == ''
      continue
    endif
    let l:ranges = split(l:errors, '}')
    for l:range in l:ranges
      " Doing precise error and warning handling.
      " The highlight will be the same as clang's carets.
      let l:pattern = '{\%(\d\+\):\(\d\+\)-\%(\d\+\):\(\d\+\)'
      let l:tmp = matchstr(l:range, l:pattern)
      let l:startcol = substitute(l:tmp, l:pattern, '\1', '')
      let l:endcol = substitute(l:tmp, l:pattern, '\2', '')
      " Highlighting the ~~~~
      let l:pat = '/\%' . l:lnum . 'l'
            \ . '\%' . l:startcol . 'c'
            \ . '.*'
            \ . '\%' . l:endcol . 'c/'
      exe 'syntax match' . l:hlgroup . l:pat
    endfor
  endfor
  return l:list
endfunction

function! s:DemangleProto(prototype)
  let l:proto = substitute(a:prototype, '[#', '', 'g')
  let l:proto = substitute(l:proto, '#]', ' ', 'g')
  let l:proto = substitute(l:proto, '#>', '', 'g')
  let l:proto = substitute(l:proto, '<#', '', 'g')
  let l:proto = substitute(l:proto, '{#.*#}', '', 'g')
  return l:proto
endfunction

let b:col = 0

function! s:ClangCompleteBinary(base)
  let l:buf = getline(1, '$')
  let l:tempfile = expand('%:p:h') . '/' . localtime() . expand('%:t')
  try
    call writefile(l:buf, l:tempfile)
  catch /^Vim\%((\a\+)\)\=:E482/
    return {}
  endtry
  let l:escaped_tempfile = shellescape(l:tempfile)

  let l:command = g:clang_exec . ' -cc1 -fsyntax-only'
        \ . ' -fno-caret-diagnostics -fdiagnostics-print-source-range-info'
        \ . ' -code-completion-at=' . l:escaped_tempfile . ':'
        \ . line('.') . ':' . b:col . ' ' . l:escaped_tempfile
        \ . ' ' . b:clang_parameters . ' ' . b:clang_user_options . ' ' . g:clang_user_options
  let l:clang_output = split(system(l:command), "\n")
  call delete(l:tempfile)

  call s:ClangQuickFix(l:clang_output, l:tempfile)
  if v:shell_error
    return []
  endif
  if l:clang_output == []
    return []
  endif

  let l:filter_str = "v:val =~ '^COMPLETION: " . a:base . "\\|^OVERLOAD: '"
  call filter(l:clang_output, l:filter_str)

  let l:res = []
  for l:line in l:clang_output

    if l:line[:11] == 'COMPLETION: ' && b:should_overload != 1

      let l:value = l:line[12:]

      let l:colonidx = stridx(l:value, ' : ')
      if l:colonidx == -1
        let l:wabbr = s:DemangleProto(l:value)
        let l:word = l:value
        let l:proto = l:value
      else
        let l:word = l:value[:l:colonidx - 1]
        " WTF is that?
        if l:word =~ '(Hidden)'
          let l:word = l:word[:-10]
        endif
        let l:wabbr = l:word
        let l:proto = l:value[l:colonidx + 3:]
      endif

      let l:kind = s:GetKind(l:proto)
      if l:kind == 't' && b:clang_complete_type == 0
        continue
      endif

      let l:word = l:wabbr
      let l:proto = s:DemangleProto(l:proto)

    elseif l:line[:9] == 'OVERLOAD: ' && b:should_overload == 1

      let l:value = l:line[10:]
      if match(l:value, '<#') == -1
        continue
      endif
      let l:word = substitute(l:value, '.*<#', '<#', 'g')
      let l:word = substitute(l:word, '#>.*', '#>', 'g')
      let l:wabbr = substitute(l:word, '<#\([^#]*\)#>', '\1', 'g')
      let l:proto = s:DemangleProto(l:value)
      let l:kind = ''
    else
      continue
    endif

    let l:item = {
          \ 'word': l:word,
          \ 'abbr': l:wabbr,
          \ 'menu': l:proto,
          \ 'info': l:proto,
          \ 'dup': 1,
          \ 'kind': l:kind }

    call add(l:res, l:item)
  endfor
  return l:res
endfunction

function! ClangComplete(findstart, base)
  if a:findstart
    let l:line = getline('.')
    let l:start = col('.') - 1
    let b:clang_complete_type = 1
    let l:wsstart = l:start
    if l:line[l:wsstart - 1] =~ '\s'
      while l:wsstart > 0 && l:line[l:wsstart - 1] =~ '\s'
        let l:wsstart -= 1
      endwhile
    endif
    if l:line[l:wsstart - 1] =~ '[(,]'
      let b:should_overload = 1
      let b:col = l:wsstart + 1
      let b:clang_type_complete = 0
      return l:wsstart
    endif
    let b:should_overload = 0
    while l:start > 0 && l:line[l:start - 1] =~ '\i'
      let l:start -= 1
    endwhile
    if l:line[l:start - 2:] =~ '->' || l:line[l:start - 1] == '.'
      let b:clang_complete_type = 0
    endif
    let b:col = l:start + 1
    return l:start
  else
    if g:clang_debug == 1
      let l:time_start = reltime()
    endif

    if g:clang_snippets == 1
      call eval('snippets#' . g:clang_snippets_engine . '#reset()')
    endif

    if g:clang_use_library == 1
      python vim.command('let l:res = ' + str(getCurrentCompletions(vim.eval('a:base'))))
    else
      let l:res = s:ClangCompleteBinary(a:base)
    endif

    if g:clang_snippets == 1
      for item in l:res
        let item['word'] = eval('snippets#' . g:clang_snippets_engine . "#add_snippet('" . item['word'] . "', '" . item['info'] . "')")
      endfor
      augroup ClangComplete
        au CursorMovedI <buffer> call s:TriggerSnippet()
      augroup end
    endif
  endif

  if g:clang_debug == 1
    echom 'clang_complete: completion time (' . (g:clang_use_library == 1 ? 'library' : 'binary') . ') '. split(reltimestr(reltime(l:time_start)))[0]
  endif
  return l:res
endif
endfunction

function! s:TriggerSnippet()
  " Dont bother doing anything until we're sure the user exited the menu
  if pumvisible() != 0
    return
  endif

  " Stop monitoring if we successfully triggered a snippet
  augroup ClangComplete
    au! CursorMovedI <buffer>
  augroup end

  " Trigger the snippet
  call eval('snippets#' . g:clang_snippets_engine . '#trigger()')
endfunction

function! ShouldComplete()
  if (getline('.') =~ '#\s*\(include\|import\)')
    return 0
  else
    if col('.') == 1
      return 1
    endif
    for l:id in synstack(line('.'), col('.') - 1)
      if match(synIDattr(l:id, 'name'), '\CComment\|String\|Number')
            \ != -1
        return 0
      endif
    endfor
    return 1
  endif
endfunction

function! LaunchCompletion()
  if ShouldComplete()
    if match(&completeopt, 'longest') != -1
      return "\<C-X>\<C-U>"
    else
      return "\<C-X>\<C-U>\<C-P>"
    endif
  else
    return ''
  endif
endfunction

function! CompleteDot()
  if g:clang_complete_auto == 1
    return '.' . LaunchCompletion()
  endif
  return '.'
endfunction

function! CompleteArrow()
  if g:clang_complete_auto != 1 || getline('.')[col('.') - 2] != '-'
    return '>'
  endif
  return '>' . LaunchCompletion()
endfunction

function! CompleteColon()
  if g:clang_complete_auto != 1 || getline('.')[col('.') - 2] != ':'
    return ':'
  endif
  return ':' . LaunchCompletion()
endfunction

" May be used in a mapping to update the quickfix window.
function! g:ClangUpdateQuickFix()
  call s:DoPeriodicQuickFix()
  return ''
endfunction

" vim: set ts=2 sts=2 sw=2 expandtab :
