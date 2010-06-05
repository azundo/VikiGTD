" The plugin for viki files to allow me to seriously get stuff done! {{{1
"
"
"
"
" Some general niceties
" Leave this out for now so I can easily source file
if !exists('b:dev_mode')
    if exists('b:loaded_viki_gtd')
        echo "not re-loading viki_gtd"
        finish
    endif
endif
let b:loaded_viki_gtd = 1

let s:save_cpo = &cpo
set cpo&vim " set this to allow linecontinuations. cpo is reset at the end

" Global var definitions {{{1
"
if !exists("g:vikiGtdProjectsDir")
    let g:vikiGtdProjectsDir = $HOME.'/Wikis/projects'
endif

" Script var definitions {{{1
"
let s:todo_begin = '^\s*\([-@]\) '

" Object Definitions {{{1
"
" Class: Utils {{{2
"
let s:Utils = {}
function! s:Utils.GetCurrentDirectory() dict "{{{3
    let current_buf = expand("%:p")
    let split_path = split(current_buf, '/')
    let current_dir = '/'.join(remove(split_path, 0, -2), '/')
    return current_dir
endfunction

function! s:Utils.LineIndent(line) dict "{{{3
    " Not that this currently counts tabs as 1. Don't use tabs! :)
    return strlen(matchstr(a:line, '^\s*'))
endfunction

function! s:Utils.CompareDates(first_date, second_date) "{{{3
    " returns 0 if equal, -1 if first_date < second_date and 1 if first_date >
    " second_date
    " first_date and second_date must be formatted as "%Y-%m-%d"

    " get equality out of the way first thing
    if a:first_date == a:second_date
        return 0
    endif

    " convert string formats to numbers to make them easily comparable
    " For ex, coverts "2010-08-05" to 20100805. Numbers are then compared for
    " gt/lt
    let first_ymd = str2nr(join(split(a:first_date, '-'), ''))
    let second_ymd = str2nr(join(split(a:second_date, '-'), ''))
    if first_ymd > second_ymd
        return 1
    else
        return -1
    endif
endfunction

function! s:Utils.RemoveDuplicates(l) "{{{3
    let val = []
    for item in a:l
        if count(val, item) == 0
            call add(val, item)
        endif
    endfor
    return val
endfunction

function! s:Utils.GetSundayForWeek(weektime)
    let offset = str2nr(strftime("%w", a:weektime))
    return a:weektime - (offset * 24 * 60 * 60)
endfunction
" Class: Todo {{{2
"
let s:Todo = {}
function! s:Todo.init() dict "{{{3
    let instance = copy(self)
    let instance.text = ""
    let instance.date = ""
    let instance.project_name = ""
    let instance.is_complete = 0
    let instance.starting_line = 0
    let instance.line_length = 0
    let instance.parent = {}
    let instance.children = []
    return instance
endfunction

function s:Todo.Delete() dict "{{{3
    let project_file = s:GetProjectIndex(self.project_name)
    if filereadable(substitute(project_file, '\(\w\+\.viki\)$', '\.\1\.swp', ''))
        echo "Project file for " . self.project_name . " is open - can't modify."
    else
        if self.starting_line != 0
            let project_file_contents = readfile(project_file)
            call remove(project_file_contents, self.starting_line - 1, self.starting_line - 1 + self.GetTreeLineLength() - 1)
            call writefile(project_file_contents, project_file)
            let msg_txt = "Removed \"$todo$\" from " . self.project_name . '.'
            if strlen(msg_txt) + strlen(self.text) - 6 < 80
                let todo_txt = self.text
            else
                " remove strlen(msg_text) then add 6 for the $todo that will
                " be replaced, then remove 3 for the ellipsis, then remove 1
                " because we're 0 indexed
                let todo_txt = self.text[:(80 - strlen(msg_txt) + 6 - 3 - 1)] . '...'
            endif
            echo substitute(msg_txt, '\$todo\$', todo_txt, '')
            return 1
        else
            echo "No starting_line for todo - could not remove."
        endif
    endif
endfunction

function s:Todo.GetTreeLineLength() dict " {{{3
    let line_length = self.line_length
    for child in self.children
        let line_length =  line_length + child.GetTreeLineLength()
    endfor
    return line_length
endfunction

function! s:Todo.ParseLines(lines, ...) dict "{{{3
    let self.line_length = len(a:lines)
    let first_line = remove(a:lines, 0)
    if match(first_line, s:todo_begin) == -1
        throw "vikiGTDError: Todo item is improperly constructed - first line does not start with a bullet point character (@ or -)."
    endif

    if matchlist(first_line, s:todo_begin)[1] == '-'
        let self.is_complete = 1
    endif

    let self.text = substitute(first_line, s:todo_begin, '', '')
    let self.text = substitute(self.text, '\s*$', '', '')
    for line in a:lines
        if match(line, s:todo_begin) != -1
            throw "vikiGTDError: Todo item is improperly constructed - additional starts with a bullet point character (@ or -)."
        endif
       let stripped_line = substitute(substitute(line, '^\s*', '', ''), '\s*$', '', '')
       let self.text = self.text . ' ' . stripped_line
    endfor
    let project_match = matchlist(self.text, ' #\(\w\+\)$')
    if !empty(project_match)
        let self.project_name = project_match[1]
        let self.text = substitute(self.text, ' #\(\w\+\)$', '', '')
    endif
    let self.date = matchstr(self.text, '\d\{4\}-\d\{2\}-\d\{2\}')
    if a:0 > 0 && type(a:1) == type(0)
        let self.starting_line = a:1
    endif
endfunction

function! s:Todo.Print(...) dict " {{{3
    let indent_level = 0
    let lines = []
    if a:0 > 0
        let indent_level = a:1
    endif
    call add(lines, repeat(' ', indent_level) . '@ ' . self.text)
    if a:0 > 1
        for child in self.children
            call add(lines, child.Print(indent_level+4, a:2))
        endfor
    endif
    if a:0 != 2 && self.project_name != ""
        " add the project tag if we're not recursivley printing, or if
        " we're explicitly told to with the existence of a third argument
        let lines[0] = lines[0] . ' #' . self.project_name
    endif
    return join(lines, "\n")
endfunction

" Class: TodoList {{{2

let s:TodoList = {}

function! s:TodoList.init() dict "{{{3
    let instance = copy(self)
    let instance.todos = []
    let instance.project_name = ""
    return instance
endfunction

function! s:TodoList.AddTodo(lines, parent, starting_line) dict "{{{3
    if a:lines != []
        let new_todo = s:Todo.init()
        call new_todo.ParseLines(a:lines, a:starting_line)
        let new_todo.project_name = self.project_name
        call add(self.todos, new_todo)
        let new_todo.parent = a:parent
        if has_key(a:parent, 'children')
            call add(a:parent['children'], new_todo)
        endif
        return new_todo
    else
        return {}
    endif
endfunction

function! s:TodoList.ParseLines(lines) dict "{{{3
    if empty(a:lines)
        return
    endif
    let lines_for_todo = []
    let line_counter = 1
    let current_todo_start = 0
    " keep track of parent todos in a stack
    " since we don't have a None in vim, use an empty
    " object (dict) as the top parent
    let parent_stack = [{},]
    " remove lines before the ** Todo
    while match(a:lines[0], '^\*\*\s*To[Dd]o') == -1
        call remove(a:lines, 0)
        if empty(a:lines)
            return
        endif
        let line_counter = line_counter + 1
    endwhile
    " Remove the **Todo line
    call remove(a:lines, 0)
    let last_line_indent = -1
    for line in a:lines
        " increment counter at the beginning of the for loop to
        " keep things simple
        " the one-off error that would have happened is negated by
        " removing the **Todo line and not incrementing the counter then
        let line_counter = line_counter + 1
        let line_indent = s:Utils.LineIndent(line)

        if line_indent == 0 
            if strlen(line) != 0
                " break if we are at a line with an indent of 0 that is not
                " empty
                break
            else
                " continue if the line is just empty
                continue
            endif
        endif

        if line_indent != last_line_indent + 2
            " here we are at a new todo item but at the same level, so add the old one
            let new_todo = self.AddTodo(lines_for_todo, parent_stack[0], current_todo_start)
            let lines_for_todo = []
            let current_todo_start = line_counter
            " Adjust the parent_stack appropriately based on indent level
            " NOTE: This code assumes 4 space indenting!!!
            if line_indent > last_line_indent
                " we are indenting so we need to add the last todo as the
                " current parent
                call insert(parent_stack, new_todo)
            elseif line_indent < last_line_indent
                " we are dedenting so we need to remove the appropriate
                " parents
                for indent_level in range((last_line_indent - line_indent)/4)
                    call remove(parent_stack, 0)
                endfor
            endif
            let last_line_indent = line_indent
        endif
        call add(lines_for_todo, line)
    endfor
    " parse the final todo item after all lines have been gone through
    call self.AddTodo(lines_for_todo, parent_stack[0], current_todo_start)
endfunction

function! s:TodoList.FilterByDate(start_date, end_date) dict "{{{3
    let filtered_list = copy(self.todos)
    let filter_function = 'v:val.date != "" && s:Utils.CompareDates(v:val.date, a:start_date) >= 0 && s:Utils.CompareDates(v:val.date, a:end_date) <= 0'
    call filter(filtered_list, filter_function)
    let new_list = s:TodoList.init()
    let new_list.todos = filtered_list
    return new_list
endfunction

function! s:TodoList.GetDueToday() dict "{{{3
    let today = strftime("%Y-%m-%d")
    return self.FilterByDate(today, today)
endfunction

function! s:TodoList.GetDueTomorrow() dict "{{{3
    let tomorrow = strftime("%Y-%m-%d", localtime() + 24*60*60)
    return self.FilterByDate(tomorrow, tomorrow)
endfunction

function! s:TodoList.GetDueTodayOrTomorrow() dict "{{{3
    let today = strftime("%Y-%m-%d")
    let tomorrow = strftime("%Y-%m-%d", localtime() + 24*60*60)
    return self.FilterByDate(today, tomorrow)
endfunction

function! s:TodoList.GetDueThisWeek() dict "{{{3
    let this_week_sunday = strftime("%Y-%m-%d", s:Utils.GetSundayForWeek(localtime()))
    let next_week_sunday = strftime("%Y-%m-%d", s:Utils.GetSundayForWeek(localtime() + 7*24*60*60))
    return self.FilterByDate(this_week_sunday, next_week_sunday)
endfunction

function! s:TodoList.GetOverdue() dict "{{{3
    let yesterday = strftime("%Y-%m-%d", localtime() - 24*60*60)
    return self.FilterByDate("0000-00-00", yesterday)
endfunction

function! s:TodoList.Print(...) dict "{{{3
    let lines = []
    if a:0 > 0 " we'll print the parents
        let temp = []
        for t in self.todos
            if t.parent == {}
                call add(temp, t)
            else
                call add(temp, t.parent)
            endif
        endfor
        let temp = s:Utils.RemoveDuplicates(temp)
        for t in temp
            " third argument here prints the project code for the parent items
            call add(lines, t.Print(4, a:1, 1))
        endfor
    else
        for t in self.todos
            call add(lines, t.Print(4))
        endfor
    endif
    return join(lines, "\n")
endfunction

" Private Functions {{{1
"
function! s:GetProjectsIndexes(...) " {{{2
    if a:0 > 0
        let directory = a:1
    else
        let directory = g:vikiGtdProjectsDir
    endif
    let index_files = split(globpath(directory, '**/*.viki'), '\n')
    let standalone_projects = split(globpath(directory, '*.viki'), '\n')
    " remove the projects/Index.viki
    call filter(standalone_projects, 'v:val !~ "Index.viki"')
    " Add the files together
    let index_files = extend(index_files, standalone_projects)
    return index_files
endfunction

function! s:ScrapeProjectDir(...) " {{{2
    if a:0 > 0
        let directory = a:1
    else
        let directory = g:vikiGtdProjectsDir
    endif
    let index_files = s:GetProjectsIndexes(directory)
    let todo_lists = {}
    for filename in index_files
        let new_list = s:TodoList.init()
        if filename =~ 'Index.viki'
            let new_list.project_name = matchlist(filename, '\(\w\+\)/Index\.viki$')[1]
        else
            let new_list.project_name = matchlist(filename, '\(\w\+\)\.viki$')[1]
        endif
        call new_list.ParseLines(readfile(filename))
        let todo_lists[new_list.project_name] =  new_list
    endfor
    return todo_lists
endfunction

function! s:GetProjectIndex(project_name, ...) " {{{2
    if a:0 > 0
        let directory = a:1
    else
        let directory = g:vikiGtdProjectsDir
    endif
    let filename = directory
    let project_name = substitute(a:project_name, '^#', '', '')
    if match(filename, '/$') == -1
        let filename = filename . '/'
    endif
    if filereadable(filename . project_name . '.viki')
        let filename = filename . project_name . '.viki'
    elseif filereadable(filename . project_name . '/Index.viki')
        let filename = filename . project_name . '/Index.viki'
    else
        throw "vikiGTDError: Project " . project_name . " does not exist."
    endif
    return filename
endfunction

function! s:ScrapeProject(project_name, ...) " {{{2
    if a:0 > 0
        let filename = s:GetProjectIndex(a:project_name, a:1)
    else
        let filename = s:GetProjectIndex(a:project_name)
    endif
    let file_lines = readfile(filename)
    let project_todo = s:TodoList.init()
    let project_todo.project_name = a:project_name
    call project_todo.ParseLines(file_lines)
    return project_todo
endfunction

function! s:CombineTodoLists(lists) "{{{2
    let combined_list = s:TodoList.init()
    if type(a:lists) == type({})
        let ls = values(a:lists)
    elseif type(a:lists) == type([])
        let ls = a:lists
    else
        throw "vikiGTDError: CombineTodoLists takes only a dictionary or list."
    endif
    for l in ls
        call extend(combined_list.todos, l.todos)
    endfor
    return combined_list
endfunction

function! s:GetTodos(filter) "{{{2
    let all_todo_lists = s:ScrapeProjectDir()
    let all_todos_list = s:CombineTodoLists(all_todo_lists)
    if a:filter == 'today'
        let filtered_todos = all_todos_list.GetDueToday()
    elseif a:filter == 'todayandtomorrow'
        let filtered_todos = all_todos_list.GetDueTodayOrTomorrow()
    elseif a:filter == 'tomorrow'
        let filtered_todos = all_todos_list.GetDueTomorrow()
    elseif a:filter == 'overdue'
        let filtered_todos = all_todos_list.GetOverdue()
    elseif a:filter == 'thisweek'
        let filtered_todos = all_todos_list.GetDueThisWeek()
    elseif a:filter == 'all'
        let filtered_todos = all_todos_list
    else
        let filtered_todos = all_todos_list
    endif
    return filtered_todos
endfunction

function! s:PrintTodos(filter) "{{{2
    let filtered_todos = s:GetTodos(a:filter)
    let split_todos = split(filtered_todos.Print(1), "\n")
    call append(line('.'), split_todos)
    exe "normal V".len(split_todos)."jgq"
endfunction

function! s:GetTodoForLine(...) "{{{2
    if a:0 > 0
        let current_line_no = a:1
    else
        let current_line_no = line('.')
    endif

    let current_line_no = line('.')
    let current_line = getline(current_line_no)
    let first_indent = s:Utils.LineIndent(current_line)
    let first_line_no = -1
    if match(current_line, s:todo_begin) != -1
        " if the current line matches the beginning of a todo, save it as the
        " first line
        let first_line_no = current_line_no
    else
        " otherwise iterate up through the file looking for a line that
        " matches.
        let current_line_no = current_line_no - 1
        while current_line_no != 0
            let current_line = getline(current_line_no)
            if match(current_line, s:todo_begin) != -1
                if s:Utils.LineIndent(current_line) == first_indent - 2
                    " if the line matches, it should be at an indent level
                    " of two less than the first line to be a proper todo
                    " set our first_indent to the indentation of the first
                    " line
                    let first_line_no = current_line_no
                    let first_indent = first_indent - 2
                endif
                break
            else
                if s:Utils.LineIndent(current_line) != first_indent
                    " break if the current indent is different than the first
                    " indent but we haven't matched a beginning of a todo item
                    break
                endif
            endif
            let current_line_no = current_line_no - 1
        endwhile
    endif
    if first_line_no == -1
        " if we didn't find a first line, return here
        return
    endif
    " find the last line of the todo so we can call getline on the range
    let current_line_no = first_line_no + 1
    " increment our line number while the indentation is two more than the
    " first line
    while s:Utils.LineIndent(getline(current_line_no)) == (first_indent + 2)
        let current_line_no = current_line_no + 1
    endwhile

    let todo_lines = getline(first_line_no, current_line_no - 1)
    let current_todo = s:Todo.init()
    call current_todo.ParseLines(todo_lines, first_line_no)
    return current_todo
endfunction

function! s:GetTopLevelTodoForLine(...) "{{{2
    if a:0 > 0
        let current_line_no = a:1
    else
        let current_line_no = line('.')
    endif
    while current_line_no > 0 && s:Utils.LineIndent(getline(current_line_no)) != 4
        if s:Utils.LineIndent(getline(current_line_no)) == 0 && getline(current_line_no) != ""
            return
        endif
        let current_line_no = current_line_no - 1
    endwhile
    if match(getline(current_line_no), s:todo_begin) != -1
        let first_line_no = current_line_no
        let current_line_no = current_line_no + 1
        while s:Utils.LineIndent(getline(current_line_no)) == 6
            let current_line_no = current_line_no + 1
        endwhile
        let top_todo = s:Todo.init()
        call top_todo.ParseLines(getline(first_line_no, current_line_no - 1))
        return top_todo
    endif
endfunction

function! s:MarkTodoUnderCursorComplete() "{{{2
    let current_todo = s:GetTodoForLine()
    if current_todo.is_complete == 1
        echo "Todo is already marked complete."
        return
    endif
    if current_todo.project_name == ""
        let toplevel_todo = s:GetTopLevelTodoForLine()
        let current_todo.project_name = toplevel_todo.project_name
    endif
    if current_todo.project_name != ""
        try
            let project_todo_list = s:ScrapeProject(current_todo.project_name)
            let todo_found = 0
            for todo in project_todo_list.todos
                if todo.text == current_todo.text
                    let todo_found = 1
                    let deleted = todo.Delete()
                    if deleted == 0
                        let c = confirm("Todo could not be deleted from project file. Still mark as completed?", "&Yes\n&No")
                        if c == 2
                            return
                        endif
                    endif
                    break
                endif
            endfor
            if todo_found == 0
                echo 'Could not find todo in project ' . current_todo.project_name '.'
            endif
        catch /vikiGTDError/
            echo 'Could not find project ' . current_todo.project_name . '. Not removing any todo item.'
        endtry
    endif
    if current_todo.starting_line != 0
        call setline(current_todo.starting_line, substitute(getline(current_todo.starting_line), '^\(\s*\)@', '\1-', ''))
    endif
endfunction

function! s:GoToProject(project_name) "{{{2
    echo a:project_name
    try
        let project_index = s:GetProjectIndex(a:project_name)
        return 'rightb vsp ' . fnameescape(project_index)
    catch /vikiGTDError/
        return 'echo "' . substitute(v:exception, 'vikiGTDError: ', '', '') . '"'
    catch
        return "echo \"error opening file: " . v:exception . v:throwpoint . "\""
    endtry
endfunction

function! s:GetProjectsToReview(freq, ...) "{{{2
    if a:0 > 0
        let directory = a:1
    else
        let directory = g:vikiGtdProjectsDir
    endif
    let project_indexes = s:GetProjectsIndexes(directory)
    let to_review = []
    for filename in project_indexes
        try
            let contents = readfile(filename)
            let review_freq = get(matchlist(contents, '^% vikiGTD:.*review\s\==\s\=\([dwm]\)'), 1, '')
            if review_freq == a:freq
                call add(to_review, filename)
            endif
        catch
            echoerr v:exception
        endtry
    endfor
    return to_review
endfunction

function! s:ReviewProjects(freq) " {{{2
    let projects = s:GetProjectsToReview(a:freq)
    if len(projects) != 0
        return 'rightb vsp | args ' . join(projects)
    else
        return 'echo "No projects to review."'
    endif
endfunction

" Public Functions {{{1

function! VikiGTDGetTodos(filter) "{{{2
    return s:GetTodos(a:filter)
endfunction

" Commands Mappings and Highlight Groups {{{1
"
" Commands {{{2
"
if !exists(":PrintTodos")
    command PrintTodos :call s:PrintTodos("todayandtomorrow")
endif

if !exists(":PrintTodosToday")
    command PrintTodosToday :call s:PrintTodos('today')
endif

if !exists(":PrintTodosThisWeek")
    command PrintTodosThisWeek :call s:PrintTodos('thisweek')
endif

if !exists(":PrintTodosTomorrow")
    command PrintTodosTomorrow :call s:PrintTodos('tomorrow')
endif

if !exists(":PrintTodosTodayAndTomorrow")
    command PrintTodosTodayAndTomorrow :call s:PrintTodos('todayandtomorrow')
endif

if !exists(":PrintTodosOverdue")
    command PrintTodosOverdue :call s:PrintTodos('overdue')
endif

if !exists(":PrintTodosAll")
    command PrintTodosAll :call s:PrintTodos('all')
endif


if !exists(":MarkTodoUnderCursorComplete")
    command MarkTodoUnderCursorComplete :call s:MarkTodoUnderCursorComplete()
endif

exe "command! ProjectReviewDaily " . s:ReviewProjects("d")

exe "command! ProjectReviewWeekly ". s:ReviewProjects("w")

exe "command! ProjectReviewMonthly ". s:ReviewProjects("m")

" Mappings {{{2
if !hasmapto('<Plug>VikiGTDMarkComplete')
    map <buffer> <unique> <LocalLeader>mc <Plug>VikiGTDMarkComplete
endif
noremap <buffer> <script> <unique> <Plug>VikiGTDMarkComplete <SID>MarkComplete
noremap <SID>MarkComplete :call <SID>MarkTodoUnderCursorComplete()<CR>

if !hasmapto('<Plug>VikiGTDGoToProject')
    map <buffer> <unique> <LocalLeader>gp <Plug>VikiGTDGoToProject
endif
noremap <buffer> <script> <unique> <Plug>VikiGTDGoToProject <SID>GoToProject
noremap <SID>GoToProject  :<C-R>=<SID>GoToProject(expand("<cword>"))<CR><CR>

" if !exists(":EchoTodoUnderCursor")
"     command EchoTodoUnderCursor :echo s:GetTodoForLine().text
" endif
" 
" if !exists(":EchoProjectUnderCursor")
"     command EchoProjectUnderCursor :echo s:GetTodoForLine().project_name
" endif

" Highlight groups {{{1
highlight VikiDate ctermfg=91
call matchadd("VikiDate", '\d\{4\}-\d\{2\}-\d\{2\}')
highlight DueToday ctermfg=Red
call matchadd("DueToday", strftime("%Y-%m-%d"))
highlight DueTomorrow ctermfg=202
call matchadd("DueTomorrow", strftime("%Y-%m-%d", localtime() + 24*60*60))

" highlight VikiGTDProject ctermfg=40
highlight VikiGTDProject ctermfg=33
call matchadd("VikiGTDProject", '#\w\+\s*$')

highlight VikiGTDCompletedItem ctermfg=236
call matchadd("VikiGTDCompletedItem", '^\s\+-\_.\{-}\(\(\n\s\+[@-]\)\|^\s*$\)\@=')
" call matchadd("VikiGTDCompletedItem", '^\*\*\s\{-}To[dD]o\_.*\(^\S\)\@!^\s\+-\_.\{-}\(\(\n\s\+[@-]\)\|^\s*$\)\@=')

" Tests {{{1
if exists('UnitTest')
    " Test Todo {{{2
    let b:test_todo = UnitTest.init("TestTodo")
    
    function! b:test_todo.TestTodoCreation() dict
        let todo = s:Todo.init()
        call self.AssertEquals(todo.text, "", "Basic todo should have empty text")
        call self.AssertEquals(todo.date, "", "Basic todo should have empty date")
    endfunction
    
    function! b:test_todo.TestParseTextOnlyTodo() dict
        let todo = s:Todo.init()
        call todo.ParseLines(["    @ A todo with a single line.",])
        call self.AssertEquals(todo.text, 'A todo with a single line.', 'Test extracting text from a simple one line todo.')
        call todo.ParseLines(["    @ A todo with ", "      multiple lines."])
        call self.AssertEquals(todo.text, 'A todo with multiple lines.')
    endfunction
    
    function! b:test_todo.TestParseTextWithDate() dict
        let todo = s:Todo.init()
        call todo.ParseLines(["    @ A todo with a single line and date 2010-05-12",])
        call self.AssertEquals(todo.date, "2010-05-12", "Simple date parsing.")
    endfunction

    function! b:test_todo.TestParseWithProject() dict
        let todo = s:Todo.init()
        let todo_lines = [
            \"    @ The first line of the todo with some stuff",
            \"      the second line, with other stuff and a #project"]
        call todo.ParseLines(todo_lines)
        call self.AssertEquals(todo.project_name, 'project')
        call self.AssertEquals(todo.text, 'The first line of the todo with some stuff the second line, with other stuff and a')
        " A regression test - this one is failing in the wild
        "
        let todo = s:Todo.init()
        call todo.ParseLines(['    @ E-mail Diana about LP stuff 2010-06-02 #LearningPartnership',])
        call self.AssertEquals(todo.project_name, 'LearningPartnership')
        call self.AssertEquals(todo.text, 'E-mail Diana about LP stuff 2010-06-02')
    endfunction

    
    " Test TodoList {{{2
    let b:test_todolist = UnitTest.init("TestTodoList")
    
    function! b:test_todolist.TestParseFile() dict "{{{3
        let current_dir = s:Utils.GetCurrentDirectory()
        let test_file = current_dir . '/fixtures/standardTodo.txt'
        let lines = readfile(current_dir . '/fixtures/standardTodo.txt')
        let new_todolist = s:TodoList.init()
        call new_todolist.ParseLines(lines)
        call self.AssertEquals(len(new_todolist.todos), 3, "TodoList should have three items.")
        call self.AssertEquals(new_todolist.todos[0].text, "A random item", "First todo item.")
        call self.AssertEquals(new_todolist.todos[0].starting_line, 2)
        call self.AssertEquals(new_todolist.todos[0].line_length, 1)
        call self.AssertEquals(new_todolist.todos[1].text, "Another random item that is longer than a single line of text so we can parse this one properly", "Second todo item.")
        call self.AssertEquals(new_todolist.todos[1].starting_line, 3)
        call self.AssertEquals(new_todolist.todos[1].line_length, 2)
        call self.AssertEquals(new_todolist.todos[2].text, "Somthing here", "Third todo item.")
        call self.AssertEquals(new_todolist.todos[2].starting_line, 5)
        call self.AssertEquals(new_todolist.todos[2].line_length, 1)
    endfunction
    
    function! b:test_todolist.TestTougherFile() dict "{{{3
        let current_dir = s:Utils.GetCurrentDirectory()
        let test_file = current_dir . '/fixtures/tougherTodo.txt'
        let lines = readfile(current_dir . '/fixtures/tougherTodo.txt')
        let new_todolist = s:TodoList.init()
        call new_todolist.ParseLines(lines)
        call self.AssertEquals(len(new_todolist.todos), 6, "TodoList should have three items.")
        call self.AssertEquals(new_todolist.todos[3].parent, new_todolist.todos[2])
        call self.AssertEquals(new_todolist.todos[0].parent, {})
        call self.AssertEquals(new_todolist.todos[1].parent, {})
        call self.AssertEquals(new_todolist.todos[2].parent, {})
        call self.AssertEquals(new_todolist.todos[4].parent, {})
        call self.AssertEquals(new_todolist.todos[5].parent, {})
        call self.AssertEquals(new_todolist.todos[2].children[0], new_todolist.todos[3])
    endfunction
    
    function! b:test_todolist.TestDateFilter() dict "{{{3
        " ok, parsing some files here which is not really unit-testy, but I'm not
        " about to write a whole json fixture parser or anything like that
        let current_dir = s:Utils.GetCurrentDirectory()
        let test_file = current_dir . '/fixtures/datedTodos.txt'
        let lines = readfile(current_dir . '/fixtures/datedTodos.txt')
        let new_todolist = s:TodoList.init()
        call new_todolist.ParseLines(lines)
    
        let filtered_todos = new_todolist.FilterByDate('0000-00-00', '9999-99-99')
        call self.AssertEquals(10, len(filtered_todos.todos))
    
        let filtered_todos = new_todolist.FilterByDate('2010-01-01', '2010-01-31')
        call self.AssertEquals(7, len(filtered_todos.todos))
    
        let filtered_todos = new_todolist.FilterByDate('2010-01-01', '2010-01-03')
        call self.AssertEquals(3, len(filtered_todos.todos))
    endfunction
    
    function! b:test_todolist.TestPrinting() dict "{{{3
        " ok, parsing some files here which is not really unit-testy, but I'm not
        " about to write a whole json fixture parser or anything like that
        let current_dir = s:Utils.GetCurrentDirectory()
        let lines = readfile(current_dir . '/fixtures/tougherTodo.txt')
        let new_todolist = s:TodoList.init()
        call new_todolist.ParseLines(lines)
        " echo new_todolist.Print()
        " echo new_todolist.Print(1)
    
        " let filtered_todos = new_todolist.FilterByDate('2010-01-01', '2010-01-31')
        " call self.AssertEquals(7, len(filtered_todos.todos))
    endfunction
    
    " Test Utils {{{2
    let b:test_utils = UnitTest.init("TestUtils")
    function! b:test_utils.TestGetDirectory() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        call self.AssertEquals(current_dir, '/home/benjamin/Code/vikiGTD/ftplugin', 'current_dir and path should be equal.') " Change this path when script is installed!
    endfunction
    
    function! b:test_utils.TestLineIndent() dict
        call self.AssertEquals(s:Utils.LineIndent("    Four spaces."), 4, "Four spaces should return an indent of 4")
        call self.AssertEquals(s:Utils.LineIndent("No spaces"), 0, "No spaces should return an indent of 0")
        call self.AssertEquals(s:Utils.LineIndent("\tA tab!"), 1, "A tab should return an indent of 1")
    endfunction
    
    function! b:test_utils.TestCompareDates() dict
        call self.AssertEquals(1, s:Utils.CompareDates("2010-08-05", "2010-08-04"))
        call self.AssertEquals(0, s:Utils.CompareDates("2010-08-05", "2010-08-05"))
        call self.AssertEquals(-1, s:Utils.CompareDates("2010-08-05", "2010-08-06"))
    endfunction
    
    function! b:test_utils.TestRemoveDuplicates() dict
        call self.AssertEquals([1, 2, 3], s:Utils.RemoveDuplicates([1, 2, 1, 2, 1, 3, 1, 2, 3, 3, 2, 1]))
    endfunction
    
    
    " Test Project Scrape Functions {{{2
    "
    let b:test_scrape = UnitTest.init("TestScrape")
    function! b:test_scrape.TestBasicScrape() dict
        let todolists = s:ScrapeProjectDir(s:Utils.GetCurrentDirectory().'/fixtures/projects')
        " call self.AssertEquals(len(todolists), 4) This gets outdated as I
        " add more fixtures, so lets leave it alone for now
        call self.AssertTrue(has_key(todolists, 'proj1'))
        call self.AssertTrue(has_key(todolists, 'proj2'))
        call self.AssertTrue(has_key(todolists, 'AnotherStandalone'))
        call self.AssertTrue(has_key(todolists, 'SingleFileProject'))
    endfunction

    function! b:test_scrape.TestProjectScrape() dict
        let todolist = s:ScrapeProject('proj1', s:Utils.GetCurrentDirectory().'/fixtures/projects')
        call self.AssertEquals(3, len(todolist.todos))
    endfunction

    function! b:test_scrape.TestProjectScrapeName() dict
        let todolist = s:ScrapeProject('proj1', s:Utils.GetCurrentDirectory().'/fixtures/projects')
        call self.AssertEquals('proj1', todolist.project_name)
        " echo todolist.Print()
        " echo todolist.Print(1)
    endfunction

    function! b:test_scrape.TestDailyReviewScrape() dict
        let project_dir = s:Utils.GetCurrentDirectory().'/fixtures/projects'
        let daily_reviews = s:GetProjectsToReview("d", project_dir)
        " echo "Daily reviews:" . string(daily_reviews)
        call self.AssertNotEquals(-1, index(daily_reviews, project_dir . '/DailyProject.viki'), string(daily_reviews) . ' does not contain DailyProject.viki')
        call self.AssertNotEquals(-1, index(daily_reviews, project_dir . '/MajorDailyProject/Index.viki'), string(daily_reviews) . ' does not contain MajorDailyProject/Index.viki')
    endfunction
    
    " Test Suite for testing all. Buffer var so we can run from command line {{{2
    let b:test_all = TestSuite.init("TestVikiGTD")
    call b:test_all.AddUnitTest(b:test_todo)
    call b:test_all.AddUnitTest(b:test_todolist)
    call b:test_all.AddUnitTest(b:test_utils)
    call b:test_all.AddUnitTest(b:test_scrape)
    
    " Add objects to FunctionRegister {{{2
    call FunctionRegister.AddObject(s:Utils, 'Utils')
    call FunctionRegister.AddObject(s:Todo, 'Todo')
    call FunctionRegister.AddObject(s:TodoList, 'Todolist')
endif

" resetting cpo option
let &cpo = s:save_cpo
" vim: foldmethod=marker
