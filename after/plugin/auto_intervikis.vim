if exists('g:vikiAutoCommandsLoaded')
    finish
endif
let g:vikiAutoCommandsLoaded = 1
if !exists('g:vikiGtdProjectsDir')
    finish
endif

function! s:GetProjectsIndexes(...)
    if a:0 > 0
        let directory = a:1
    else
        let directory = g:vikiGtdProjectsDir
    endif
    let index_files = split(globpath(directory, '**/Index.viki'), '\n')
    let standalone_projects = split(globpath(directory, '*.viki'), '\n')
    " Add the files together
    let index_files = extend(index_files, standalone_projects)
    " remove the projects/Index.viki
    call filter(index_files, 'v:val != "' . directory . '/Index.viki"')
    return index_files
endfunction

function! s:AutoSetProjectInterVikis()
    if !exists('g:vikiGtdProjectsDir')
        return
    endif
    let index_files = s:GetProjectsIndexes()
    for index_file in index_files
        if index_file =~ 'Index.viki$'
            let m = matchlist(index_file, '\(.*/\(\w\+\)\)/Index.viki$')
            let viki_dir = m[1]
            let viki_name = m[2]
            " let viki_name = matchlist(index_file, '/\(\w\+\)/Index.viki$')[1]

            exe 'let g:vikiInter' . toupper(viki_name) . ' = "' . viki_dir . '"'
            exe 'let g:vikiInter' . toupper(viki_name) .'_suffix = ".viki"'
            " this command is what we really want at the end of the day - allows us
            " to type :PROJECTNAME and get the project index
            exe 'command -bang -nargs=? -complete=customlist,viki#EditComplete ' . viki_name . ' call viki#Edit(empty(<q-args>) ? "' . toupper(viki_name) . '::Index" : viki#InterEditArg("'.toupper(viki_name).'", <q-args>), "<bang>")'
        else
            let viki_name = matchlist(index_file, '/\(\w\+\).viki$')[1]
            exe 'command ' . viki_name . ' e ' . index_file
        endif
    endfor
endfunction

call s:AutoSetProjectInterVikis()

function! s:GetSundayForWeek(weektime)
    let offset = str2nr(strftime("%w", a:weektime))
    return a:weektime - (offset * 24 * 60 * 60)
endfunction

" Set up some other helpful commands for habits app
exec "command Today edit ".$HOME."/Wikis/habits/weeks/days/".strftime("%Y-%m-%d", localtime()).".viki"
exec "command Tomorrow edit ".$HOME."/Wikis/habits/weeks/days/".strftime("%Y-%m-%d", localtime() + 24*60*60).".viki"
exec "command Yesterday edit ".$HOME."/Wikis/habits/weeks/days/".strftime("%Y-%m-%d", localtime() - 24*60*60).".viki"
exec "command ThisWeek edit ".$HOME."/Wikis/habits/weeks/".strftime("%Y-%m-%d", s:GetSundayForWeek(localtime())).".viki"
exec "command LastWeek edit ".$HOME."/Wikis/habits/weeks/".strftime("%Y-%m-%d", s:GetSundayForWeek(localtime() - 7*24*60*60)).".viki"
