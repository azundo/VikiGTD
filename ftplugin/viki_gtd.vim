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

function! s:Utils.GetSundayForWeek(weektime) "{{{3
    let offset = str2nr(strftime("%w", a:weektime))
    return a:weektime - (offset * 24 * 60 * 60)
endfunction


" Class: Project {{{2
"
let s:Project = {}

function! s:Project.init(name, ...) dict "{{{3
    TVarArg ['project_directory', g:vikiGtdProjectsDir]
    let instance = copy(self)
    let instance.name = a:name
    let instance.project_directory = project_directory
    let instance.index_file = instance.GetOwnIndexFile()
    let instance.todo_list = {}
    let instance.waiting_for_list = {}
    return instance
endfunction

function! s:Project.GetAllIndexFiles(...) dict "{{{3
    TVarArg ['directory', g:vikiGtdProjectsDir]
    let index_files = split(globpath(directory, '**/Index.viki'), '\n')
    let standalone_projects = split(globpath(directory, '*.viki'), '\n')
    " Add the files together
    let index_files = extend(index_files, standalone_projects)
    " remove the projects/Index.viki
    call filter(index_files, 'v:val !~ "' . directory . '/Index.viki"')
    return index_files
endfunction

function! s:Project.GetIndexFile(project_name, ...) dict "{{{3
    TVarArg ['directory', g:vikiGtdProjectsDir]
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

function! s:Project.ScrapeDirectory(...) dict " {{{3
    TVarArg ['directory', g:vikiGtdProjectsDir]
    let index_files = self.GetAllIndexFiles(directory)
    let projects = {}
    for filename in index_files
        if filename =~ 'Index.viki'
            let new_proj = s:Project.init(matchlist(filename, '\(\w\+\)/Index\.viki$')[1], directory)
        else
            let new_proj = s:Project.init(matchlist(filename, '\(\w\+\)\.viki$')[1], directory)
        endif
        call new_proj.Scrape()
        let projects[new_proj.name] =  new_proj
    endfor
    return projects
endfunction

function! s:Project.GetProjectNames(...) dict " {{{3
    TVarArg ['directory', g:vikiGtdProjectsDir]
    let directory = g:vikiGtdProjectsDir
    let index_files = self.GetAllIndexFiles(directory)
    let project_names = []
    for filename in index_files
        if filename =~ 'Index.viki'
            call add(project_names, matchlist(filename, '\(\w\+\)/Index\.viki$')[1])
        else
            call add(project_names, matchlist(filename, '\(\w\+\)\.viki$')[1])
        endif
    endfor
    return project_names
endfunction

function! s:Project.GetOwnIndexFile() dict "{{{3
    let filename = self.project_directory
    if match(filename, '/$') == -1
        let filename = filename . '/'
    endif
    if filereadable(filename . self.name . '.viki')
        let filename = filename . self.name . '.viki'
    elseif filereadable(filename . self.name . '/Index.viki')
        let filename = filename . self.name . '/Index.viki'
    else
        throw "vikiGTDError: Project " . self.name . " does not exist."
    endif
    return filename
endfunction

function! s:Project.Scrape() dict " {{{3
    let file_lines = readfile(self.index_file)

    let project_todo = s:TodoList.init()
    let project_todo.project_name = self.name
    call project_todo.ParseLines(file_lines)
    let self.todo_list = project_todo

    let project_waiting_for = s:WaitingForList.init()
    let project_waiting_for.project_name = self.name
    call project_waiting_for.ParseLines(file_lines)
    let self.waiting_for_list = project_waiting_for
endfunction

function! s:Project.GetProjectsToReview(freq, ...) "{{{3
    TVarArg ['directory', g:vikiGtdProjectsDir]
    let project_indexes = self.GetAllIndexFiles(directory)
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

"
" Class: Item {{{2
"
let s:Item = {}
function! s:Item.init() dict "{{{3
    let instance = copy(self)
    let instance.text = ""
    let instance.date = ""
    let instance.project_name = ""
    let instance.is_complete = 0
    let instance.starting_line = -1
    let instance.line_length = 0
    let instance.parent = {}
    let instance.children = []
    let instance.begin_pattern = '^\s*\([-@]\) '
    let instance.list_class = s:ItemList
    return instance
endfunction

function s:Item.Equals(other_item) dict "{{{3
    return self.text == a:other_item.text
endfunction

function s:Item.Delete() dict "{{{3
    let project_file = s:Project.GetIndexFile(self.project_name)
    if filereadable(substitute(project_file, '\(\w\+\.viki\)$', '\.\1\.swp', ''))
        echo "Project file for " . self.project_name . " is open - can't modify."
        return
    endif
    if self.starting_line != -1
        let project_file_contents = readfile(project_file)
        call remove(project_file_contents, self.starting_line, self.starting_line + self.GetTreeLineLength() - 1)
        call writefile(project_file_contents, project_file)
        let msg_txt = "Removed \"$item$\" from " . self.project_name . '.'
        if strlen(msg_txt) + strlen(self.text) - 6 < 80
            let item_txt = self.text
        else
            " remove strlen(msg_text) then add 6 for the $item that will
            " be replaced, then remove 3 for the ellipsis, then remove 1
            " because we're 0 indexed
            let item_txt = self.text[:(80 - strlen(msg_txt) + 6 - 3 - 1)] . '...'
        endif
        echo substitute(msg_txt, '\$item\$', item_txt, '')
        return 1
    else
        echo "No starting_line for item - could not remove."
    endif
endfunction

function s:Item.GetTreeLineLength() dict " {{{3
    if self.starting_line != -1 && len(self.children) != 0 && self.children[-1].starting_line != -1
        let line_length = self.children[-1].starting_line - self.starting_line + self.children[-1].GetTreeLineLength()
    else
        let line_length = self.line_length
        for child in self.children
            let line_length =  line_length + child.GetTreeLineLength()
        endfor
    endif
    return line_length
endfunction

function! s:Item.ParseLines(lines, ...) dict "{{{3
    let self.line_length = len(a:lines)
    let first_line = remove(a:lines, 0)
    if match(first_line, self.begin_pattern) == -1
        throw "vikiGTDError: Item is improperly constructed - first line does not start with a bullet point character (@ or -)."
    endif

    if matchlist(first_line, self.begin_pattern)[1] == '-'
        let self.is_complete = 1
    endif

    let self.text = substitute(first_line, self.begin_pattern, '', '')
    let self.text = substitute(self.text, '\s*$', '', '')
    for line in a:lines
        if match(line, self.begin_pattern) != -1
            throw "vikiGTDError: Item is improperly constructed - additional line starts with a bullet point character (@ or -)."
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

function! s:Item.Print(...) dict " {{{3
    TVarArg ['indent_level', 0], ['recursive', 0], ['print_project_name', 0]
    let lines = []
    let line_marker = (self.is_complete == 1) ? '-' : '@'
    call add(lines, repeat(' ', indent_level) . line_marker . ' ' . self.text)
    if recursive != 0
        for child in self.children
            call add(lines, child.Print(indent_level+4, recursive))
        endfor
    endif
    if (print_project_name != 0 || recursive == 0 ) && self.project_name != ""
        " add the project tag if we're not recursivley printing, or if
        " we're explicitly told to with the existence of a third argument
        let lines[0] = lines[0] . ' #' . self.project_name
    endif
    return join(lines, "\n")
endfunction

function! s:Item.GetItemOnLine(...) dict " {{{3
    TVarArg ['current_line_no', line('.') - 1], ['lines', getline(0, '$')]
    let item = self.init()
    let current_line = lines[current_line_no]
    let first_indent = s:Utils.LineIndent(current_line)
    let first_line_no = -1
    if match(current_line, item.begin_pattern) != -1
        " if the current line matches the beginning of a todo, save it as the
        " first line
        let first_line_no = current_line_no
    else
        " otherwise iterate up through the file looking for a line that
        " matches.
        let current_line_no = current_line_no - 1
        while current_line_no != 0
            let current_line = lines[current_line_no]
            if match(current_line, item.begin_pattern) != -1
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
    while len(lines) > current_line_no && s:Utils.LineIndent(lines[current_line_no]) == (first_indent + 2)
        let current_line_no = current_line_no + 1
    endwhile

    let item_lines = lines[first_line_no : current_line_no - 1]
    call item.ParseLines(item_lines, first_line_no) " A dirty hack for now - TODO refactor to be similar to ItemList.ParseLines
    return item
endfunction

function! s:Item.GetTopLevelItemForLine(...) dict " {{{{3
    TVarArg ['current_line_no', line('.') - 1], ['lines', getline(0, '$')]
    let top_item = self.init()
    while current_line_no >= 0 && s:Utils.LineIndent(lines[current_line_no]) != 4
        if s:Utils.LineIndent(lines[current_line_no]) == 0 && lines[current_line_no] != ""
            return
        endif
        let current_line_no = current_line_no - 1
    endwhile
    if match(lines[current_line_no], top_item.begin_pattern) != -1
        let first_line_no = current_line_no
        let current_line_no = current_line_no + 1
        while s:Utils.LineIndent(lines[current_line_no]) == 6
            let current_line_no = current_line_no + 1
        endwhile
        call top_item.ParseLines(lines[first_line_no : current_line_no - 1])
        return top_item
    endif
endfunction

function! s:Item.GetItemTreeOnLine(line, ...) dict " {{{3
    TVarArg ['lines', getline(0, '$')]
    let line = a:line
    while line >= 0 && s:Utils.LineIndent(lines[line]) != 4
        if s:Utils.LineIndent(lines[line]) == 0 && lines[line] != ""
            return self.init()
        endif
        let line = line - 1
    endwhile
    let item_tree = self.init()
    if match(lines[line], item_tree.begin_pattern) != -1
        let first_line_no = line
        let line = line + 1
        while len(lines) > line
            if s:Utils.LineIndent(lines[line]) == 4
                break
            elseif s:Utils.LineIndent(lines[line]) == 0 && lines[line] != ''
                break
            endif
            let line = line + 1
        endwhile
        let item_list = item_tree.list_class.init()
        call item_list.ParseItemLines(lines[first_line_no : line - 1])
    endif
    return item_list.items[0]
endfunction


" Class: ItemList {{{2

let s:ItemList = {}

function! s:ItemList.init() dict "{{{3
    let instance = copy(self)
    let instance.items = []
    let instance.project_name = ""
    let instance.item_class = s:Item
    let instance.start_pattern = '^\*\*\s*\w\+'
    let instance.starting_line = -1
    let instance.ending_line = -1
    let instance.file_name = ''
    return instance
endfunction

function! s:ItemList.CombineLists(lists) dict "{{{3
    let combined_list = self.init()
    if type(a:lists) == type({})
        let ls = values(a:lists)
    elseif type(a:lists) == type([])
        let ls = a:lists
    else
        throw "vikiGTDError: CombineLists takes only a dictionary or list."
    endif
    for l in ls
        call extend(combined_list.items, l.items)
    endfor
    return combined_list
endfunction

function! s:ItemList.ParseItem(lines, parent, starting_line) dict "{{{3
    if a:lines != []
        let new_item = self.item_class.init()
        call new_item.ParseLines(a:lines, a:starting_line)
        let new_item.project_name = self.project_name
        call add(self.items, new_item)
        let new_item.parent = a:parent
        if has_key(a:parent, 'children')
            call add(a:parent['children'], new_item)
        endif
        return new_item
    else
        return {}
    endif
endfunction

function! s:ItemList.ParseLines(lines, ...) dict "{{{3
    TVarArg ['line_offset', 0], 'file_name'
    if empty(a:lines)
        return
    endif
    let self.file_name = file_name
    let lines_for_item = []
    let line_counter = 0
    let current_item_start = 0
    " keep track of parent items in a stack
    " since we don't have a None in vim, use an empty
    " object (dict) as the top parent
    let parent_stack = [{},]
    " remove lines before the start_pattern
    while match(a:lines[line_counter], self.start_pattern) == -1
        " call remove(a:lines, 0)
        let line_counter = line_counter + 1
        if line_counter == len(a:lines)
            return
        endif
    endwhile
    let self.starting_line = line_counter + line_offset
    let last_line_indent = -1
    while line_counter < len(a:lines) - 1
        let line_counter = line_counter + 1
        if match(a:lines[line_counter], '^\S') != -1
            " break if we are at a line with non-space as the first character
            " remove a line from the line counter so we are at the last line
            " in the list
            let line_counter = line_counter - 1
            break
        endif
    endwhile
    while match(a:lines[line_counter], '^\(\s*\|\S.*\)$') != -1 && match(a:lines[line_counter], self.start_pattern) == -1
        let line_counter = line_counter -1
    endwhile
    let self.ending_line = line_counter + line_offset
    call self.ParseItemLines(a:lines[self.starting_line + 1 - line_offset : self.ending_line - line_offset], self.starting_line + 1)
endfunction

function! s:ItemList.ParseItemLines(lines, ...) dict " {{{3
    TVarArg ['line_offset', 0]
    let line_counter = -1
    let lines_for_item = []
    let current_item_start = 0
    let last_line_indent = -1
    " keep track of parent items in a stack
    " since we don't have a None in vim, use an empty
    " object (dict) as the top parent
    let parent_stack = [{},]
    while line_counter < len(a:lines) - 1
        let line_counter = line_counter + 1
        let line = a:lines[line_counter]
        let line_indent = s:Utils.LineIndent(line)
        if match(line, '^\s*$') != -1
            " continue if we are on a blank line
            continue
        endif

        if line_indent != last_line_indent + 2 
            " here we are at a new item item but at the same level, so add the old one
            let new_item = self.ParseItem(lines_for_item, parent_stack[0], current_item_start + line_offset)
            let lines_for_item = []
            let current_item_start = line_counter
            " Adjust the parent_stack appropriately based on indent level
            " NOTE: This code assumes 4 space indenting!!!
            if line_indent > last_line_indent
                " we are indenting so we need to add the last item as the
                " current parent
                call insert(parent_stack, new_item)
            elseif line_indent < last_line_indent
                " we are dedenting so we need to remove the appropriate
                " parents
                for indent_level in range((last_line_indent - line_indent)/4)
                    call remove(parent_stack, 0)
                endfor
            endif
            let last_line_indent = line_indent
        endif
        call add(lines_for_item, line)
    endwhile
    " parse the final item item after all lines have been gone through
    call self.ParseItem(lines_for_item, parent_stack[0], current_item_start + line_offset)
endfunction


function! s:ItemList.GetListForLine(line_no, ...) " {{{3
    TVarArg ['lines', getline(1, '$')], ['file_name', expand("%:p")]
    if a:0 == 0
        let a:line_no = a:line_no - 1 " adjust to be zero based
    endif
    let current_line = a:line_no
    while current_line >= 0
        if match(lines[current_line], self.start_pattern) != -1
            return self.ParseLines(lines[current_line :], current_line)
        endif
        let current_line = current_line - 1
    endwhile
    throw "vikiGTDError: No list on given line."
endfunction

function! s:ItemList.FilterByDate(start_date, end_date) dict "{{{3
    let filtered_list = copy(self.items)
    let filter_function = 'v:val.date != "" && s:Utils.CompareDates(v:val.date, a:start_date) >= 0 && s:Utils.CompareDates(v:val.date, a:end_date) <= 0'
    call filter(filtered_list, filter_function)
    let new_list =self.init()
    let new_list.items = filtered_list
    return new_list
endfunction

function! s:ItemList.FilterByNaturalLanguageDate(filter) dict "{{{3
    let today = strftime("%Y-%m-%d")
    let tomorrow = strftime("%Y-%m-%d", localtime() + 24*60*60)
    let this_week_sunday = strftime("%Y-%m-%d", s:Utils.GetSundayForWeek(localtime()))
    let next_week_sunday = strftime("%Y-%m-%d", s:Utils.GetSundayForWeek(localtime() + 7*24*60*60))
    let yesterday = strftime("%Y-%m-%d", localtime() - 24*60*60)
    if a:filter == 'Today'
        let filtered_items = self.FilterByDate(today, today)
    elseif a:filter == 'TodayAndTomorrow'
        let filtered_items = self.FilterByDate(today, tomorrow)
    elseif a:filter == 'Tomorrow'
        let filtered_items = self.FilterByDate(tomorrow, tomorrow)
    elseif a:filter == 'Overdue'
        let filtered_items = self.FilterByDate("0000-00-00", yesterday)
    elseif a:filter == 'ThisWeek'
        let filtered_items = self.FilterByDate(this_week_sunday, next_week_sunday)
    elseif a:filter == 'All'
        let filtered_items = self.FilterByDate("0000-00-00", "9999-99-99")
    elseif a:filter == ''
        " get overdue up to tomorrow if filter is blank
        let filtered_items = self.FilterByDate("0000-00-00", tomorrow)
    else
        let filtered_items = self.FilterByDate("0000-00-00", "9999-99-99")
    endif
    return filtered_items
endfunction


function! s:ItemList.Print(...) dict "{{{3
    let lines = []
    if a:0 > 0 " we'll print the parents
        let temp = []
        for t in self.items
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
        for t in self.items
            call add(lines, t.Print(4))
        endfor
    endif
    return join(lines, "\n")
endfunction

function! s:ItemList.AddItem(item, ...) dict " {{{3
    TVarArg ['do_execute', 1]
    let exe_txt = ''
    if self.file_name == '' && self.project_name != ''
        let self.file_name = s:Project.GetIndexFile(self.project_name)
    endif

    if self.file_name == '' || !filereadable(self.file_name)
        let exe_txt = 'echo "No file name for that item list found."'
    elseif self.ending_line == -1
        let exe_txt = 'echo "No ending line set for this item list - cannot add an item."'
    elseif filereadable(substitute(self.file_name, '\(\w\+\.viki\)$', '\.\1\.swp', ''))
        let bufname = matchstr(self.file_name, '\w\+\(Index\)\?.viki$')
        if bufname == '' || bufnr(bufname) == -1
            let exe_txt = 'echo "Project file for ' . self.project_name . ' is open - cannot modify."'
        endif
    endif
    if exe_txt == ''
        let item_line = a:item.Print(4)
        let current_tab = tabpagenr()
        let execute_statements = [
            \"tabe " . self.file_name,
            \"call append(" . string(self.ending_line + 1) . ", '" . item_line . "')",
            \"call cursor(" . string(self.ending_line + 2) . ", 1)",
            \" exe \"normal Vgq\"",
            \"wq",
            \"tabn " . current_tab,
            \"echo 'Added " . a:item.text . " to " . self.file_name . ".'"
            \]

        let exe_txt = join(execute_statements, ' | ')
    endif
    " echo exe_txt
    if do_execute == 1
        exe exe_txt
    endif
    return exe_txt
endfunction
" Class: Todo {{{2
let s:Todo = copy(s:Item)

function! s:Todo.init() dict " {{{3
    let instance = s:Item.init()
    call extend(instance, copy(s:Todo), "force")
    let instance.list_class = s:TodoList
    return instance
endfunction

" Class: TodoList {{{2
let s:TodoList = copy(s:ItemList)

function! s:TodoList.init() dict "{{{3
    let instance = s:ItemList.init()
    " "force" means that we override anything in instance with anything in
    " copy of self
    call extend(instance, copy(s:TodoList), "force")
    let instance.item_class = s:Todo
    let instance.ParseTodo = instance.ParseItem
    let instance.start_pattern = '^\*\*\s*To[dD]o'
    return instance
endfunction

" Class: WaitingForList {{{2
let s:WaitingForList = copy(s:ItemList)
function! s:WaitingForList.init() dict "{{{3
    let instance = s:ItemList.init()
    call extend(instance, copy(s:WaitingForList), "force")
    let instance.start_pattern = '^\*\*\s*Waiting'
    return instance
endfunction



" Private Functions {{{1
"

function! s:GetItemLists(list_type, filter) " {{{2
    let all_projects = values(s:Project.ScrapeDirectory())
    let all_item_lists = []
    let proto = all_projects[0][ a:list_type ].init()
    for proj in all_projects
        if proj[a:list_type] != {} && len(proj[a:list_type].items) != 0
            call add(all_item_lists, proj[a:list_type])
        endif
    endfor
    let all_items_list = proto.CombineLists(all_item_lists)
    let filtered_items = all_items_list.FilterByNaturalLanguageDate(a:filter)
    return filtered_items
endfunction


function! s:PrintItems(list_type, filter)
    let filtered_items = s:GetItemLists(a:list_type, a:filter)
    let split_items = split(filtered_items.Print(1), "\n")
    if len(split_items) > 0
        call append(line('.'), split_items)
        " format the items to the correct text width with gq
        exe "normal V".len(split_items)."jgq"
    else
        echo "No items found for that query."
    endif
endfunction

function! s:OpenItemsInSp(item_type, filter) "{{{2
    let commands = []
    call add(commands, "rightb vsp /tmp/vikiList.viki")
    call add(commands, "set buftype=nofile")
    call add(commands, "set bufhidden=delete")
    call add(commands, "setlocal noswapfile")
    call add(commands, "map <buffer> q :q<CR>")
    call add(commands, "Print" . a:item_type .  a:filter)
    return ':' . join(commands, ' | ')
endfunction



function! s:MarkTodoUnderCursorComplete() "{{{2
    let current_todo = s:Todo.GetItemOnLine()
    if current_todo.is_complete == 1
        echo "Todo is already marked complete."
        return
    endif
    if current_todo.project_name == ""
        let toplevel_todo = s:Todo.GetTopLevelItemForLine()
        let current_todo.project_name = toplevel_todo.project_name
    endif
    if current_todo.project_name != ""
        try
            let proj = s:Project.init(current_todo.project_name)
            call proj.Scrape()
            let project_todo_list = proj.todo_list
            let todo_found = 0
            for todo in project_todo_list.items
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
    if current_todo.starting_line != -1
        call setline(current_todo.starting_line + 1, substitute(getline(current_todo.starting_line + 1), '^\(\s*\)@', '\1-', ''))
        exe "w"
    endif
endfunction

function! s:GoToProject(project_name) "{{{2
    try
        let project_index = s:Project.GetIndexFile(a:project_name)
        return 'rightb vsp ' . fnameescape(project_index)
    catch /vikiGTDError/
        return 'echo "' . substitute(v:exception, 'vikiGTDError: ', '', '') . '"'
    catch
        return "echo \"error opening file: " . v:exception . v:throwpoint . "\""
    endtry
endfunction


function! s:ReviewProjects(freq) " {{{2
    let projects = s:Project.GetProjectsToReview(a:freq)
    if len(projects) != 0
        return 'rightb vsp | args ' . join(projects)
    else
        return 'echo "No projects to review."'
    endif
endfunction

function! s:AddTodoCmd(project_name) " {{{2
    let todo_text = input("Enter todo text:\n")
    if todo_text == ''
        return
    endif
    let p = s:Project.init(a:project_name)
    call p.Scrape()
    let td = s:Todo.init()
    let td.text = todo_text
    return p.todo_list.AddItem(td, 0)
endfunction

function! s:AddWaitingForCmd(project_name) " {{{2
    let wf_text = input("Enter waiting for text:\n")
    if wf_text == ''
        return
    endif
    let p = s:Project.init(a:project_name)
    call p.Scrape()
    let wf = s:Item.init()
    let wf.text = wf_text
    return p.waiting_for_list.AddItem(wf, 0)
endfunction

" Public Functions {{{1

function! VikiGTDGetTodos(filter) "{{{2
    return s:GetItemLists('todo_list', a:filter)
endfunction

function! b:VikiGTDGetProjectNamesForAutocompletion(...) "{{{2
    let project_names = s:Project.GetProjectNames()
    return join(project_names, "\n")
endfunction

" Commands Mappings and Highlight Groups {{{1
"
" Commands {{{2
"
let s:date_ranges = ['', 'Today', 'Tomorrow', 'ThisWeek', 'TodayAndTomorrow', 'Overdue', 'All']
for date_range in s:date_ranges

    if !exists(":Todos" . date_range)
        exe "command Todos" . date_range .  " " . s:OpenItemsInSp("Todos", date_range)
    endif

    if !exists(":PrintTodos" . date_range)
        exe "command PrintTodos" . date_range . " :call s:PrintItems(\"todo_list\", \"" . date_range . "\")"
    endif

    if !exists(":PrintWfs" . date_range)
        exe "command PrintWfs" . date_range . " :call s:PrintItems(\"waiting_for_list\", \"" . date_range . "\")"
    endif

    if !exists(":Wfs" . date_range)
        exe "command Wfs" . date_range .  " " . s:OpenItemsInSp("Wfs", date_range)
    endif

endfor


if !exists(":MarkTodoUnderCursorComplete")
    command MarkTodoUnderCursorComplete :call s:MarkTodoUnderCursorComplete()
endif

if !exists(":ProjectReviewDaily")
    exe "command! ProjectReviewDaily " . s:ReviewProjects("d")
endif

if !exists(":ProjectReviewWeekly")
    exe "command! ProjectReviewWeekly ". s:ReviewProjects("w")
endif

if !exists(":ProjectReviewMonthly")
    exe "command! ProjectReviewMonthly ". s:ReviewProjects("m")
endif

if !exists(":AddTodo")
    command -nargs=1 -complete=custom,b:VikiGTDGetProjectNamesForAutocompletion AddTodo :exe s:AddTodoCmd(<f-args>)
endif

if !exists(":AddWaitingFor")
    command -nargs=1 -complete=custom,b:VikiGTDGetProjectNamesForAutocompletion AddWaitingFor :exe s:AddWaitingForCmd(<f-args>)
endif

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
"
" Add match
highlight VikiGTDOverdueDate cterm=Bold ctermfg=Red
" highlight VikiGTDOverdueItem cterm=Underline
function! b:AddOverdueDates()
    let current_lines = getline(1, '$')
    let dates = []
    let today = str2nr(strftime("%Y%m%d"))
    " assume only one date per line for now...
    for line in current_lines
        let date = matchstr(line, '\d\{4}-\d\{2}-\d\{2}')
        if date != ""
            call add(dates, date)
        endif
    endfor
    for date in dates
        if str2nr(substitute(date, '-', '', 'g')) < today
            call matchadd("VikiGTDOverdueDate", date)
            " call matchadd("VikiGTDOverdueItem", '^\s\+@\_.\{-}' . date . '\_.\{-}\(\(\n\s\+[@-]\)\|^\s*$\)\@=')
        endif
    endfor
endfunction

call b:AddOverdueDates()

" Tests {{{1
if exists('UnitTest')
    " Test ItemList {{{2
    "
    "
    let b:test_itemlist = UnitTest.init("TestItemList")
    
    function! b:test_itemlist.TestGetListForLine() dict
        let lines = readfile(s:Utils.GetCurrentDirectory() . '/fixtures/genList.txt')
        let new_list = s:ItemList.init()
        call new_list.GetListForLine(0, lines) " make it easy to start
        call self.AssertEquals(9, len(new_list.items))

        let new_list = s:ItemList.init()
        call new_list.GetListForLine(5, lines) " make it easy to start
        call self.AssertEquals(9, len(new_list.items))
        call self.AssertEquals(0, new_list.starting_line)
        call self.AssertEquals(12, new_list.ending_line)

        let new_list = s:ItemList.init()
        call new_list.GetListForLine(14, lines) " make it easy to start
        call self.AssertEquals(3, len(new_list.items))
        call self.AssertEquals(14, new_list.starting_line)
        call self.AssertEquals(17, new_list.ending_line)

    endfunction

    function! b:test_itemlist.TestCombineLists() dict
        let first = s:TodoList.init()
        let second = s:TodoList.init()
        let first_todo = s:Todo.init()
        let first_todo.text = "test"
        let second_todo = s:Todo.init()
        let second_todo.text = "something here"
        call add(first.items, first_todo)
        call add(second.items, second_todo)
        let third_list = s:TodoList.CombineLists([first, second])
        call self.AssertNotEquals(-1, index(third_list.items, first_todo))
        call self.AssertNotEquals(-1, index(third_list.items, second_todo))
        call self.AssertEquals(s:Todo, third_list.item_class)
    endfunction

    " Test Project {{{2
    let b:test_project = UnitTest.init("TestProject")

    function! b:test_project.TestGetProjectLocation() dict
        let p = s:Project.init('TestProject', s:Utils.GetCurrentDirectory() . '/fixtures/projects')
        call self.AssertEquals('TestProject', p.name)
        call self.AssertEquals(s:Utils.GetCurrentDirectory() . '/fixtures/projects/TestProject.viki', p.index_file)
        call p.Scrape()
        call self.AssertEquals(2, len(p.todo_list.items))
        call self.AssertEquals(2, p.todo_list.starting_line)
        call self.AssertEquals(4, p.todo_list.ending_line)

        call self.AssertEquals(3, len(p.waiting_for_list.items))
        call self.AssertEquals(6, p.waiting_for_list.starting_line)
        call self.AssertEquals(9, p.waiting_for_list.ending_line)
    endfunction

    function! b:test_project.TestGetProjectIndexes() dict
        let here = s:Utils.GetCurrentDirectory()
        let test_projects = here . '/fixtures/projects'
        let project_indexes = s:Project.GetAllIndexFiles(test_projects)
        call self.AssertNotEquals(-1, index(project_indexes, test_projects . '/MajorDailyProject/Index.viki'))
        call self.AssertNotEquals(-1, index(project_indexes, test_projects. '/SingleFileProject.viki'))
        call self.AssertNotEquals(-1, index(project_indexes, test_projects . '/TestProject.viki'))
    endfunction

    function! b:test_project.TestGetProjectIndex() dict
        let here = s:Utils.GetCurrentDirectory()
        let test_projects = here . '/fixtures/projects'
        call self.AssertEquals(test_projects . '/MajorDailyProject/Index.viki', s:Project.GetIndexFile('MajorDailyProject', test_projects))
        call self.AssertEquals(test_projects . '/SingleFileProject.viki', s:Project.GetIndexFile('SingleFileProject', test_projects))
    endfunction


    " Test Item {{{2
    let b:test_item = UnitTest.init("TestItem")

    function! b:test_item.TestGetItemOnLine() dict
        let here = s:Utils.GetCurrentDirectory()
        let lines = readfile(here.'/fixtures/testGetItemOnLine.txt')
        let item = s:Item.GetItemOnLine(1, lines)
        call self.AssertEquals('Item one', item.text)

        let item = s:Item.GetItemOnLine(3, lines)
        call self.AssertEquals('nested item', item.text)

        let item = s:Item.GetItemOnLine(4, lines)
        call self.AssertEquals('Something with multiple lines that continue further and further', item.text)
        let item = s:Item.GetItemOnLine(5, lines)
        call self.AssertEquals('Something with multiple lines that continue further and further', item.text)
        let item = s:Item.GetItemOnLine(6, lines)
        call self.AssertEquals('Something with multiple lines that continue further and further', item.text)

        let item = s:Item.GetItemOnLine(7, lines)
        call self.AssertEquals('Another item', item.text)

        let item = s:Item.GetItemOnLine(9, lines)
        call self.AssertEquals('Another guy after a space', item.text)

        let item = s:Item.GetItemOnLine(10, lines)
        call self.AssertEquals('One with a date 2010-06-05', item.text)
        call self.AssertEquals('2010-06-05', item.date)
    endfunction

    function! b:test_item.TestGetItemTreeOnLine() dict
        let here = s:Utils.GetCurrentDirectory()
        let lines = readfile(here.'/fixtures/testGetItemTreeOnLine.txt')
        let item_tree = s:Item.GetItemTreeOnLine(1, lines)
        call self.AssertEquals('Level one', item_tree.text)
        call self.AssertEquals(2, len(item_tree.children))
        call self.AssertEquals(1, len(item_tree.children[0].children))
        call self.AssertEquals(0, len(item_tree.children[1].children))
    endfunction

    " Test ItemList {{{2
    let b:test_itemlist = UnitTest.init("TestItem")

    function! b:test_itemlist.TestParseItemLines() dict "{{{3
        let here = s:Utils.GetCurrentDirectory()
        let lines = readfile(here.'/fixtures/testParseItemLines.txt')
        let il = s:ItemList.init()
        call il.ParseItemLines(lines)
        let parents = filter(il.items, 'v:val.parent == {}')
        call self.AssertEquals(0, len(il.items[0].children))
        call self.AssertEquals(3, len(il.items[1].children))
    endfunction


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
        call self.AssertEquals(len(new_todolist.items), 3, "TodoList should have three items.")
        call self.AssertEquals(new_todolist.items[0].text, "A random item", "First todo item.")
        call self.AssertEquals(new_todolist.items[0].starting_line, 1, 'starting line should be 1')
        call self.AssertEquals(new_todolist.items[0].line_length, 1, 'line length should also be 1')
        call self.AssertEquals(new_todolist.items[1].text, "Another random item that is longer than a single line of text so we can parse this one properly", "Second todo item.")
        call self.AssertEquals(new_todolist.items[1].starting_line, 2, 'starting line should be 2')
        call self.AssertEquals(new_todolist.items[1].line_length, 2, 'line length should also be 2')
        call self.AssertEquals(new_todolist.items[2].text, "Somthing here", "Third todo item.")
        call self.AssertEquals(new_todolist.items[2].starting_line, 4, 'starting line should be 4')
        call self.AssertEquals(new_todolist.items[2].line_length, 1, 'line length should be 1')
    endfunction
    
    function! b:test_todolist.TestTougherFile() dict "{{{3
        let current_dir = s:Utils.GetCurrentDirectory()
        let test_file = current_dir . '/fixtures/tougherTodo.txt'
        let lines = readfile(current_dir . '/fixtures/tougherTodo.txt')
        let new_todolist = s:TodoList.init()
        call new_todolist.ParseLines(lines)
        call self.AssertEquals(len(new_todolist.items), 6, "TodoList should have three items.")
        call self.AssertEquals(new_todolist.items[3].parent, new_todolist.items[2])
        call self.AssertEquals(new_todolist.items[0].parent, {})
        call self.AssertEquals(new_todolist.items[1].parent, {})
        call self.AssertEquals(new_todolist.items[2].parent, {})
        call self.AssertEquals(new_todolist.items[4].parent, {})
        call self.AssertEquals(new_todolist.items[5].parent, {})
        call self.AssertEquals(new_todolist.items[2].children[0], new_todolist.items[3])
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
        call self.AssertEquals(10, len(filtered_todos.items))
    
        let filtered_todos = new_todolist.FilterByDate('2010-01-01', '2010-01-31')
        call self.AssertEquals(7, len(filtered_todos.items))
    
        let filtered_todos = new_todolist.FilterByDate('2010-01-01', '2010-01-03')
        call self.AssertEquals(3, len(filtered_todos.items))
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
        " call self.AssertEquals(7, len(filtered_todos.items))
    endfunction

    function! b:test_todo.TestGetTreeLineLength() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        let lines = readfile(current_dir . '/fixtures/trickyChildrenList.txt')
        let new_list = s:ItemList.init()
        call new_list.ParseLines(lines)
        call self.AssertEquals(1, new_list.items[0].GetTreeLineLength())
        call self.AssertEquals(2, new_list.items[1].GetTreeLineLength())
        call self.AssertEquals(4, new_list.items[2].GetTreeLineLength())
        call self.AssertEquals(8, new_list.items[6].GetTreeLineLength())
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
        let all_projects = s:Project.ScrapeDirectory(s:Utils.GetCurrentDirectory().'/fixtures/projects')
        let todolists = {}
        for proj in values(all_projects)
            if proj.todo_list != {}
                let todolists[proj.name] = proj.todo_list
            endif
        endfor
        " call self.AssertEquals(len(todolists), 4) This gets outdated as I
        " add more fixtures, so lets leave it alone for now
        call self.AssertTrue(has_key(todolists, 'proj1'))
        call self.AssertTrue(has_key(todolists, 'proj2'))
        call self.AssertTrue(has_key(todolists, 'AnotherStandalone'))
        call self.AssertTrue(has_key(todolists, 'SingleFileProject'))
    endfunction

    function! b:test_scrape.TestProjectScrape() dict
        let proj = s:Project.init('proj1', s:Utils.GetCurrentDirectory().'/fixtures/projects')
        call proj.Scrape()
        let todolist = proj.todo_list
        call self.AssertEquals(3, len(todolist.items))
    endfunction

    function! b:test_scrape.TestProjectScrapeName() dict
        let proj = s:Project.init('proj1', s:Utils.GetCurrentDirectory().'/fixtures/projects')
        call proj.Scrape()
        let todolist = proj.todo_list
        call self.AssertEquals('proj1', todolist.project_name)
        " echo todolist.Print()
        " echo todolist.Print(1)
    endfunction

    function! b:test_scrape.TestDailyReviewScrape() dict
        let project_dir = s:Utils.GetCurrentDirectory().'/fixtures/projects'
        let daily_reviews = s:Project.GetProjectsToReview("d", project_dir)
        " echo "Daily reviews:" . string(daily_reviews)
        call self.AssertNotEquals(-1, index(daily_reviews, project_dir . '/DailyProject.viki'), string(daily_reviews) . ' does not contain DailyProject.viki')
        call self.AssertNotEquals(-1, index(daily_reviews, project_dir . '/MajorDailyProject/Index.viki'), string(daily_reviews) . ' does not contain MajorDailyProject/Index.viki')
    endfunction

    function! b:test_scrape.TestScrapeProjEmptyTodo() dict
        let proj = s:Project.init('EmptyTodo', s:Utils.GetCurrentDirectory().'/fixtures/projects')
        call proj.Scrape()
        let todolist = proj.todo_list
        call self.AssertEquals(8, todolist.starting_line)
        call self.AssertEquals(8, todolist.ending_line)
    endfunction

    let b:test_get_item_lists = UnitTest.init("TestGetItems")


    " Test Suite for testing all. Buffer var so we can run from command line {{{2
    let b:test_all = TestSuite.init("TestVikiGTD")
    call b:test_all.AddUnitTest(b:test_todo)
    call b:test_all.AddUnitTest(b:test_item)
    call b:test_all.AddUnitTest(b:test_todolist)
    call b:test_all.AddUnitTest(b:test_utils)
    call b:test_all.AddUnitTest(b:test_scrape)
    call b:test_all.AddUnitTest(b:test_itemlist)
    call b:test_all.AddUnitTest(b:test_project)
    call b:test_all.AddUnitTest(b:test_get_item_lists)
    
    " Add objects to FunctionRegister {{{2
    call FunctionRegister.AddObject(s:Utils, 'Utils')
    call FunctionRegister.AddObject(s:Todo, 'Todo')
    call FunctionRegister.AddObject(s:TodoList, 'Todolist')
endif

" resetting cpo option
let &cpo = s:save_cpo
" vim: foldmethod=marker
