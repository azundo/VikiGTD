function! s:AutoSetProjectInterVikis()
python << EOF
import vim, os
home_dir = os.path.expandvars('$HOME')
projects_path = os.path.join(home_dir, 'Wikis', 'projects')
def is_valid_interviki(path):
    """ Checks to make sure that the path is a directory and contains an
        Index.viki.
    """
    return os.path.isdir(path) and os.path.exists(os.path.join(path, 'Index.viki'))
def set_up_intervikis(projects_path):
    """
    Sets up the intervikis after checking to make sure the projects_path exists.
    """
    if not os.path.exists(projects_path):
        return
    projects_contents = os.listdir(projects_path)
    
    project_dirs = [entry for entry in projects_contents if is_valid_interviki(os.path.join(projects_path, entry))]
    for dir in project_dirs:
        viki_name = dir.upper()
        # not using the projects_path here since it uses os specific path separator
        # and vim doesn't want that.
        viki_location = 'let g:vikiInter%s = $HOME."/Wikis/projects/%s"' % (viki_name, dir)
        viki_suffix = 'let g:vikiInter%s_suffix = ".viki"' % viki_name
        # this command is what we really want at the end of the day - allows us
        # to type :PROJECTNAME and get the project index
        viki_command = 'command -bang -nargs=? -complete=customlist,viki#EditComplete %s call viki#Edit(empty(<q-args>) ? "%s::Index" : viki#InterEditArg("%s", <q-args>), "<bang>")' % (dir, viki_name, viki_name)
        # execute the commands
        vim.command(viki_location)
        vim.command(viki_suffix)
        vim.command(viki_command)
set_up_intervikis(projects_path)
EOF
endfunction

call s:AutoSetProjectInterVikis()

function! s:GetSundayForWeek(weektime)
    let offset = str2nr(strftime("%w", a:weektime))
    return a:weektime - (offset * 24 * 60 * 60)
endfunction

" Set up some other helpful commands for habits app
exec "command Today edit ".$HOME."/Wikis/habits/weeks/days/".strftime("%Y-%m-%d", localtime()).".viki"
exec "command Yesterday edit ".$HOME."/Wikis/habits/weeks/days/".strftime("%Y-%m-%d", localtime() - 24*60*60).".viki"
exec "command ThisWeek edit ".$HOME."/Wikis/habits/weeks/".strftime("%Y-%m-%d", s:GetSundayForWeek(localtime())).".viki"
exec "command LastWeek edit ".$HOME."/Wikis/habits/weeks/".strftime("%Y-%m-%d", s:GetSundayForWeek(localtime() - 7*24*60*60)).".viki"
