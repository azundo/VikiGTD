function! s:AutoSetProjectInterVikis()
python << EOF
import vim, os
home_dir = os.path.expandvars('$HOME')
projects_path = os.path.join(home_dir, 'Wikis', 'projects')
projects_contents = os.listdir(projects_path)

def is_valid_interviki(path):
    """ Checks to make sure that the path is a directory and contains an
        Index.viki.
    """
    return os.path.isdir(path) and os.path.exists(os.path.join(path, 'Index.viki'))
project_dirs = [entry for entry in projects_contents if is_valid_interviki(os.path.join(projects_path, entry))]
for dir in project_dirs:
    viki_name = dir.upper()
    # not using the projects_path here since it uses os specific path separator
    # and vim doesn't want that.
    viki_location = 'let g:vikiInter%s = $HOME."/Wikis/projects/%s"' % (viki_name, dir)
    viki_suffix = 'let g:vikiInter%s_suffix = ".viki"' % viki_name
    # this command is what we really want at the end of the day - allows us
    # to type :PROJECTNAME and get the project index
    viki_command = 'command -bang -nargs=? -complete=customlist,viki#EditComplete %s call viki#Edit(empty(<q-args>) ? "%s::Index" : viki#InterEditArg("%s", <q-args>), "<bang>")' % (viki_name, viki_name, viki_name)
    # execute the commands
    vim.command(viki_location)
    vim.command(viki_suffix)
    vim.command(viki_command)
EOF
endfunction

call s:AutoSetProjectInterVikis()
