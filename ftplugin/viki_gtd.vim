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
if !exists("g:vikiGtdHome")
    let g:vikiGtdHome = $HOME.'/Wikis'
endif
if !exists("g:vikiGtdProjectsDir")
    let g:vikiGtdProjectsDir = g:vikiGtdHome.'/projects'
endif
if !exists("g:vikiGtdLogDir")
    let g:vikiGtdLogDir = g:vikiGtdHome.'/log'
endif
if !exists("g:vikiGtdDB")
    if has("win32") || has("win64")
        let g:vikiGtdDB = $HOME.'/vimfiles/_vikiGtdDB'
    else
        let g:vikiGtdDB = $HOME.'/.vim/.vikiGtdDB'
    endif
endif

if !exists("s:db_psh")
    let s:db_psh = g:vikiGtdDB.'/modified_time.psh'
endif

if !exists("g:python_path")
    if has("win32") || has("win64")
        let g:python_path = ['C:\\Users\\Ben\\vimfiles\\py']
    else
        let g:python_path = ['/home/benjamin/.vim/py']
    endif
endif


" Script var definitions {{{1
"
let s:todo_begin = '^\s*\([-@]\) '

" Object Definitions {{{1
"
" Class: Utils {{{2
"
let s:Utils = {}
let s:Utils.day_map = {
    \'sun': 'Sunday', 
    \'mon': 'Monday', 
    \'tue': 'Tuesday',
    \'wed': 'Wednesday',
    \'thu': 'Thursday',
    \'fri': 'Friday',
    \'sat': 'Saturday',
    \}
function! s:Utils.GetCurrentDirectory() dict "{{{3
    return fnamemodify(expand("%:p"), ":h")
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
    " check for 0 (empty string) and put those dates last
    if first_ymd > second_ymd
        return (second_ymd != 0) ? 1 : -1
    else
        return (first_ymd != 0) ? -1 : 1
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

function! s:Utils.GetDayTimeForDayName(dayname) "{{{3
    let today = localtime()
    let sunday = s:Utils.GetSundayForWeek(today)
    " onset is opposite of offset - getting value for the dayname
    let onset = 0
    if a:dayname == "Sunday"
        let onset = 0
    elseif a:dayname == "Monday"
        let onset = 1
    elseif a:dayname == "Tuesday"
        let onset = 2
    elseif a:dayname == "Wednesday"
        let onset = 3
    elseif a:dayname == "Thursday"
        let onset = 4
    elseif a:dayname == "Friday"
        let onset = 5
    elseif a:dayname == "Saturday"
        let onset = 6
    endif
    let daytime = sunday + (onset * 24 * 60 * 60)
    return daytime
endfunction

function! s:Utils.GetDateForDayName(dayname) " {{{3
    return strftime("%Y-%m-%d", s:Utils.GetDayTimeForDayName(a:dayname))
endfunction

function! s:Utils.GetNextDateForDayName(dayname) " {{{3
    let daytime = s:Utils.GetDayTimeForDayName(a:dayname)
    let today = localtime()
    " move daytime to the next week if we are before today
    if daytime < today
        let daytime = daytime + 7 * 24 * 60 * 60
    endif
    return strftime("%Y-%m-%d", daytime)
endfunction

function! s:Utils.SubstituteDates(text) "{{{3
    let text = a:text
    for day in keys(s:Utils.day_map)
        let text = substitute(text, '\<' . day . '\>', s:Utils.GetNextDateForDayName(s:Utils.day_map[day]), 'g')
        let text = substitute(text, '\<' . s:Utils.day_map[day] . '\>', s:Utils.GetNextDateForDayName(s:Utils.day_map[day]), 'g')
    endfor
    return text
endfunction

" Class: Sorter {{{2
let s:Sorter = {
            \'sort_functions': []
            \}

function! s:Sorter.reset() " {{{3
    let s:Sorter.sort_functions = []
endfunction


function! s:Sorter.SortByDate(first, second) " {{{3
    if type(a:first) != type(a:second)
        throw "vikiGTDError: args to s:SortByDate must be same type."
    endif

    if type(a:first) == type("str")
        return s:Utils.CompareDates(a:first, a:second)
    elseif type(a:first) == type({}) && has_key(a:first, "date") && has_key(a:second, "date")
        return s:Utils.CompareDates(a:first['date'], a:second['date'])
    else
        throw "vikiGTDError: args to s:SortByDate must be string or dictionary with date key."
    endif
endfunction

function! s:Sorter.SortByContext(first, second) " {{{3
    if type(a:first) != type(a:second)
        throw "vikiGTDError: args to Sorting Functions must be same type."
    endif

    if type(a:first) == type("str")
        let fst = a:first
        let second = a:second
    elseif type(a:first) == type({}) && has_key(a:first, "context") && has_key(a:second, "context")
        let fst = a:first['context']
        let second = a:second['context']
    else
        throw "vikiGTDError: args to s:Sorter.SortByContext must be string or dictionary with context key."
    endif
    return (fst == second) ? 0 : (fst < second) ? (fst != '' ? -1 : 1) : (second != '' ? 1 : -1)
endfunction

function! s:Sorter.SortByPriority(first, second) " {{{3
    if type(a:first) != type(a:second)
        throw "vikiGTDError: args to Sorting Functions must be same type."
    endif
    if type(a:first) == type("str")
        let fst = a:first
        let second = a:second
    elseif type(a:first) == type({}) && has_key(a:first, "priority") && has_key(a:second, "priority")
        let fst = a:first['priority']
        let second = a:second['priority']
    else
        throw "vikiGTDError: args to s:Sorter.SortByPriority must be string or dictionary with priority key."
    endif

    if fst == second
        return 0
    elseif fst == '!!'
        return -1
    elseif second == '!!'
        return 1
    elseif fst = '#!'
        return -1
    elseif second == '#!'
        return 1
    else
        return 0
    endif
endfunction


function! s:Sorter.AddSortFunction(f) " {{{3
    let s:Sorter.sort_functions = add(s:Sorter.sort_functions, a:f)
endfunction

function! s:SorterSort(first, second, ...) " {{{3
    TVarArg ['function_index', 0]
    if len(s:Sorter.sort_functions) < function_index + 1
        " return a:first == a:second ? 0 : a:first < a:second ? -1 : 1
        " we've run out of sorting functions, so they're equal
        return 0
    endif
    if type(s:Sorter.sort_functions[function_index]) == type(function("tr"))
        let Next_sort_fun = s:Sorter.sort_functions[function_index]
    else
        let Next_sort_fun = function(s:Sorter.sort_functions[function_index])
    endif
    let next_sort_result = call(Next_sort_fun, [a:first, a:second], s:Sorter)
    if next_sort_result == 0
        return s:SorterSort(a:first, a:second, function_index + 1)
    else
        return next_sort_result
    endif
endfunction

function! s:SortByDate(first, second) " {{{3
    call s:Sorter.reset()
    call s:Sorter.AddSortFunction(s:Sorter.SortByDate)
    return s:SorterSort(a:first, a:second)
endfunction

function! s:SortByContext(first, second) " {{{3
    call s:Sorter.reset()
    call s:Sorter.AddSortFunction(s:Sorter.SortByContext)
    return s:SorterSort(a:first, a:second)
endfunction

function! s:SortByDateContext(first, second) " {{{3
    call s:Sorter.reset()
    call s:Sorter.AddSortFunction(s:Sorter.SortByDate)
    call s:Sorter.AddSortFunction(s:Sorter.SortByContext)
    return s:SorterSort(a:first, a:second)
endfunction

function! s:SortByDatePriority(first, second) " {{{3
    call s:Sorter.reset()
    call s:Sorter.AddSortFunction(s:Sorter.SortByDate)
    call s:Sorter.AddSortFunction(s:Sorter.SortByPriority)
    return s:SorterSort(a:first, a:second)
endfunction

function! s:SortByPriorityDate(first, second) " {{{3
    call s:Sorter.reset()
    call s:Sorter.AddSortFunction(s:Sorter.SortByPriority)
    call s:Sorter.AddSortFunction(s:Sorter.SortByDate)
    return s:SorterSort(a:first, a:second)
endfunction

" Class: Project {{{2
"
let s:Project = {}
let s:Project.list_types = {}

function! s:Project.init(name, ...) dict "{{{3
    TVarArg ['project_directory', g:vikiGtdProjectsDir]
    let instance = copy(s:Project)
    let instance.name = a:name
    let instance.project_directory = project_directory
    let instance.index_file = instance.GetOwnIndexFile()
    call instance.AddLists()
    return instance
endfunction

function! s:Project.RegisterList(l) dict " {{{3
    let self.list_types[a:l.list_type] = a:l
endfunction

function! s:Project.AddLists() dict " {{{3
    for list_type in keys(self.list_types)
        let self[list_type] = {}
    endfor
endfunction
function! s:Project.GetAllIndexFiles(...) dict "{{{3
    TVarArg ['directory', g:vikiGtdProjectsDir]
    let index_files = split(globpath(directory, '**/Index.viki'), '\n')
    let standalone_projects = split(globpath(directory, '*.viki'), '\n')
    " Add the files together
    let index_files = extend(index_files, standalone_projects)
    " sub \ with / when on windows
    if has("win32") || has("win64")
        let sub_func = 'substitute(v:val, "\\\\", "/", "g")'
        let index_files = map(index_files, sub_func)
        let directory = substitute(directory, "\\\\", "/", "g")
    endif
    " remove the projects/Index.viki
    call filter(index_files, 'v:val !~ "' . directory . '/Index.viki"')
    " remove the project archives
    call filter(index_files, 'v:val !~ "ProjectArchives"')
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
        throw "vikiGTDError: Project " . project_name . " does not exist. In s:Project.GetIndexFile."
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
        throw "vikiGTDError: Project " . self.name . " does not exist. In s:Project.GetOwnIndexFile()"
    endif
    return filename
endfunction

function! s:Project.Scrape() dict " {{{3
    let file_lines = readfile(self.index_file)

    for list_type in keys(self.list_types)
        let item_list = self.list_types[list_type].init()
        let item_list.project_name = self.name
        call item_list.ParseLines(file_lines)
        let self[list_type] = item_list
    endfor
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

function! s:Project.GetNameFromIndexFile(...) "{{{3
    TVarArg ['filename', expand('%:p')]
    let p_name_match = matchlist(filename, '/\(\w\+\)\(/Index\)\?\(\.viki\)$')
    return get(p_name_match, 1, '')
endfunction

"
" Class: Item {{{2
"
let s:Item = {}
function! s:Item.init() dict "{{{3
    let instance = copy(s:Item)
    let instance.text = ""
    let instance.date = ""
    let instance.context = ""
    let instance.contact = ""
    let instance.project_name = ""
    let instance.is_complete = 0
    let instance.starting_line = -1
    let instance.line_length = 0
    let instance.parent = {}
    let instance.children = []
    let instance.begin_pattern = '^\s*\([-@]\) '
    let instance.list_class = s:ItemList
    let instance.priority = ""
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
        throw "vikiGTDError: Item is improperly constructed - first line does not start with a bullet point character (@ or -). " . first_line
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
    " remove pomodoro references
    let self.text = substitute(self.text, '\s*[Xx]\+\s*$', '', '')
    let self.date = matchstr(self.text, '\d\{4\}-\d\{2\}-\d\{2\}')
    " get context @context
    let self.context = matchstr(self.text, '\w\@<!@\w\+\>')
    " get contact &contact
    let self.contact = matchstr(self.text, '\w\@<!&\w\+\>')
    " get priority rating !! or #!
    let self.priority = matchstr(self.text, '\w\@<![#!]!\w\@<!')
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

function! s:Item.GetTopLevelItemForLine(...) dict " {{{3
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

function! s:Item.GetItemTreeOnLine(...) dict " {{{3
    TVarArg ['line', line('.') - 1], ['lines', getline(0, '$')]
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

function! s:Item.GetOldestAncestor() dict " {{{3
    return empty(self.parent) ? self : self.parent.GetOldestAncestor()
endfunction


" Class: ItemList {{{2

let s:ItemList = {}
let s:ItemList.list_type = 'item_list'
let s:ItemList.subclasses = []

function! s:ItemList.init() dict "{{{3
    let instance = copy(s:ItemList)
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
        if new_item.project_name == '' && self.project_name != ''
            let new_item.project_name = self.project_name
        endif
        call add(self.items, new_item)
        let new_item.parent = a:parent
        if has_key(a:parent, 'children')
            call add(a:parent['children'], new_item)
        endif
        if has_key(a:parent, 'project_name') && a:parent.project_name != '' && new_item.project_name == ''
            let new_item.project_name = a:parent.project_name
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


function! s:ItemList.GetListForLine(...) " {{{3
    TVarArg ['current_line', line('.') - 1], ['lines', getline(1, '$')]
    while current_line >= 0
        if match(lines[current_line], self.start_pattern) != -1
            return self.ParseLines(lines[current_line :], current_line)
        endif
        let current_line = current_line - 1
    endwhile
    throw "vikiGTDError: No list on given line."
endfunction

function! s:ItemList.Filter(filter_function, ...) dict " {{{3
    TVarArg ['filter_children', 0]
    let filtered_items = copy(self.items)
    call filter(filtered_items, a:filter_function)
    if filter_children
        for item in filtered_items
            let item.children = filter(item.children, a:filter_function)
        endfor
    endif
    let self.items = filtered_items
    return self
endfunction

function! s:ItemList.Sort(sort_function, ...) dict "{{{3
    TVarArg ['sort_children', 0]
    let sorted_list = copy(self.items)
    call sort(sorted_list, a:sort_function)
    if sort_children
        for item in sorted_items
            call sort(item.children, a:sort_function)
        endfor
    endif
    let self.items = sorted_list
    return self
endfunction

function! s:ItemList.FilterByDate(start_date, end_date) dict "{{{3
    let filter_function = 'v:val.date != "" && s:Utils.CompareDates(v:val.date, "' . a:start_date . '") >= 0 && s:Utils.CompareDates(v:val.date, "' . a:end_date . '") <= 0'
    return filter_function
endfunction

function! s:ItemList.FilterByNaturalLanguageDate(filter) dict "{{{3
    let today = strftime("%Y-%m-%d")
    let tomorrow = strftime("%Y-%m-%d", localtime() + 24*60*60)
    let this_week_sunday = strftime("%Y-%m-%d", s:Utils.GetSundayForWeek(localtime()))
    let next_week_sunday = strftime("%Y-%m-%d", s:Utils.GetSundayForWeek(localtime() + 7*24*60*60))
    let yesterday = strftime("%Y-%m-%d", localtime() - 24*60*60)
    if a:filter == 'Today'
        let filter_function = s:ItemList.FilterByDate(today, today)
    elseif a:filter == 'TodayAndTomorrow'
        let filter_function = s:ItemList.FilterByDate(today, tomorrow)
    elseif a:filter == 'Tomorrow'
        let filter_function = s:ItemList.FilterByDate(tomorrow, tomorrow)
    elseif a:filter == 'Overdue'
        let filter_function = s:ItemList.FilterByDate("0000-00-01", yesterday)
    elseif a:filter == 'ThisWeek'
        let filter_function = s:ItemList.FilterByDate(this_week_sunday, next_week_sunday)
    elseif a:filter == 'All'
        let filter_function = s:ItemList.FilterByDate("0000-00-01", "9999-99-99")
    elseif a:filter == 'Undated'
        let filter_function = s:ItemList.Filter('v:val.date == ""', 1)
    elseif a:filter == ''
        " get overdue up to tomorrow if filter is blank
        let filter_function = s:ItemList.FilterByDate("0000-00-01", tomorrow)
    else
        let filter_function = s:ItemList.FilterByDate("0000-00-01", "9999-99-99")
    endif
    return filter_function
endfunction


function! s:ItemList.Print(...) dict "{{{3
    let lines = []
    if a:0 > 0 " we'll print the parents
        let temp = []
        for t in self.items
            call add(temp, t.GetOldestAncestor())
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
    " checks for an existing swap file
    elseif filereadable(substitute(self.file_name, '\(\w\+\.viki\)$', '\.\1\.swp', ''))
        let bufname = matchstr(self.file_name, '\w\+\(Index\)\?.viki$')
        " use bufnr to check if the file is opened in this instance of vim. If
        " so, no problem. If not, we can't edit it
        if bufname == '' || bufnr(bufname) == -1
            let exe_txt = 'echo "Project file for ' . self.project_name . ' is open - cannot modify."'
        endif
    endif
    if exe_txt == ''
        let item_lines = split(a:item.Print(4, 1, 1), "\n")
        let current_tab = tabpagenr()
        let execute_statements = [
            \"tabe " . self.file_name,
            \"call append(" . string(self.ending_line + 1) . ", " . string(item_lines) . ")",
            \"call cursor(" . string(self.ending_line + 2) . ", 1)",
            \" exe \"normal Vgq\"",
            \"wq",
            \"tabn " . current_tab,
            \"redraw",
            \"echo \"Added " . escape(a:item.text, '"') . " to " . self.file_name . ".\""
            \]

        let exe_txt = join(execute_statements, ' | ')
    endif
    " echo exe_txt
    if do_execute == 1
        exe exe_txt
    endif
    return exe_txt
endfunction

function! s:ItemList.GetListTypeOnLine(...) dict " {{{3
    TVarArg ['current_line_no', line('.') - 1], ['lines', getline(0, '$')]
    while current_line_no >= 0 && match(lines[current_line_no], '^\S') == -1
        let current_line_no = current_line_no - 1
    endwhile
    let sc_instances = map(copy(self.subclasses), 'v:val.init()')
    for sc in sc_instances
        if match(lines[current_line_no], sc.start_pattern ) != -1
            return sc.list_type
        endif
    endfor
    return ''
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
let s:TodoList.list_type = 'todo_list'
call s:Project.RegisterList(s:TodoList)
call add(s:ItemList.subclasses, s:TodoList)

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
let s:WaitingForList.list_type = 'waiting_for_list'
call s:Project.RegisterList(s:WaitingForList)
call add(s:ItemList.subclasses, s:WaitingForList)


function! s:WaitingForList.init() dict "{{{3
    let instance = s:ItemList.init()
    call extend(instance, copy(s:WaitingForList), "force")
    let instance.start_pattern = '^\*\*\s*Waiting'
    return instance
endfunction

" Class: AppointmentList {{{2
let s:AppointmentList = copy(s:ItemList)
let s:AppointmentList.list_type = 'appointment_list'
call s:Project.RegisterList(s:AppointmentList)
call add(s:ItemList.subclasses, s:AppointmentList)

function! s:AppointmentList.init() dict "{{{3
    let instance = s:ItemList.init()
    call extend(instance, copy(s:AppointmentList), "force")
    let instance.start_pattern = '^\*\*\s*App'
    return instance
endfunction

" Class: SetupList {{{2
let s:SetupList = copy(s:ItemList)
let s:SetupList.list_type = 'todo_list' " TODO since SetupList equates to TodoList - maybe should rename
call add(s:ItemList.subclasses, s:SetupList)
function! s:SetupList.init() dict "{{{3
    let instance = s:ItemList.init()
    call extend(instance, copy(s:SetupList), "force")
    let instance.start_pattern = '^\*\*\s*Set\( \)\?up'
    return instance
endfunction

function! s:SetupList.GetSetupForDate(...) dict "{{{3
    TVarArg ['date', strftime("%Y-%m-%d")]
    let setup = self.init()
    let setup_file = g:vikiGtdLogDir . '/weeks/days/' . date . '.viki' 
    if filereadable(setup_file)
        call setup.ParseLines(readfile(setup_file), 0, setup_file)
    endif
    return setup
endfunction



" Private Functions {{{1
"

function! s:GetItemLists(list_type, ...) " {{{2
    TVarArg ['directory', g:vikiGtdProjectsDir]
    let all_projects = values(s:Project.ScrapeDirectory(directory))
    let all_item_lists = []
    let proto = all_projects[0][ a:list_type ].init()
    for proj in all_projects
        if proj[a:list_type] != {} && len(proj[a:list_type].items) != 0
            call add(all_item_lists, proj[a:list_type])
        endif
    endfor
    let all_items_list = proto.CombineLists(all_item_lists)
    return all_items_list
endfunction



function! s:PrintItems(list_type, ...) " {{{2
    TVarArg ['filters', []], ['sort_function', 0]
    let item_list = s:GetItemLists(a:list_type)
    for filter in filters
        let item_list = item_list.Filter(filter)
    endfor
    if type(sort_function) == type("") &&  len(sort_function) > 0
        let item_list = item_list.Sort(sort_function)
    endif
    let split_items = split(item_list.Print(1), "\n")
    if len(split_items) > 0
        call append(line('.'), split_items)
        " format the items to the correct text width with gq
        exe "normal V".len(split_items)."jgq"
    else
        echo "No items found for that query."
    endif
endfunction

function! s:CopyUndoneTodos() " {{{2
    let setup = s:SetupList.init()
    let days_back = 1
    while setup.file_name == '' && days_back < 10 "don't go back more than 10 days
        let setup = s:SetupList.GetSetupForDate(strftime("%Y-%m-%d", localtime() - 24*60*60*days_back))
        let days_back = days_back + 1
    endwhile
    let filtered_setup = setup.Filter('v:val.is_complete == 0', 1)
    let split_items = split(filtered_setup.Print(1), "\n")
    if len(split_items) > 0
        call append(line('.'), split_items)
        " format the items to the correct text width with gq
        exe "normal V".len(split_items)."jgq"
    else
        echo "No undone todos found in yesterday's file."
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

function! s:RunCmdInSp(c) "{{{2
    let commands = []
    call add(commands, "rightb vsp /tmp/vikiList.viki")
    call add(commands, "set buftype=nofile")
    call add(commands, "set bufhidden=delete")
    call add(commands, "setlocal noswapfile")
    call add(commands, "map <buffer> q :q<CR>")
    call add(commands, a:c)
    return ':' . join(commands, ' | ')
endfunction

function! s:MarkItemUnderCursorComplete() "{{{2
    let current_item = s:Item.GetItemOnLine()
    if current_item.is_complete == 1
        echo "Item is already marked complete."
        return
    endif
    if current_item.starting_line != -1
        call setline(current_item.starting_line + 1, substitute(getline(current_item.starting_line + 1), '^\(\s*\)@', '\1-', ''))
        exe "w"
    else
        return
    endif
    let list_type = s:ItemList.GetListTypeOnLine()
    if current_item.project_name == ""
        let toplevel_item = s:Item.GetTopLevelItemForLine()
        let current_item.project_name = toplevel_item.project_name
    endif
    if current_item.project_name != "" && list_type != ""
        try
            let proj = s:Project.init(current_item.project_name)
            call proj.Scrape()
            if has_key(proj, list_type)
                let project_list = proj[list_type]
                let item_found = 0
                for item in project_list.items
                    if item.Equals(current_item)
                        let item_found = 1
                        let deleted = item.Delete()
                        if deleted == 0
                            let c = confirm("Item could not be deleted from project file. Still mark as completed?", "&Yes\n&No")
                            if c == 2
                                call setline(current_item.starting_line + 1, substitute(getline(current_item.starting_line + 1), '^\(\s*\)-', '\1@', ''))
                                exe "w"
                                return
                            endif
                        endif
                        break
                    endif
                endfor
                if item_found == 0
                    echo 'Could not find item in project ' . current_item.project_name '.'
                endif
            endif
        catch /vikiGTDError/
            echo 'Could not find project ' . current_item.project_name . '. Not removing any item.'
        endtry
    endif
endfunction

function! s:GoToProject() "{{{2
    let toplevel_item = s:Item.GetTopLevelItemForLine()
    if toplevel_item.project_name == ''
        return
    endif
    try
        let project_index = s:Project.GetIndexFile(toplevel_item.project_name)
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
    let todo_text = s:Utils.SubstituteDates(todo_text)
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

function! s:AddAppointmentCmd(project_name) " {{{2
    let app_text = input("Enter appointment text:\n")
    if app_text == ''
        return
    endif
    let p = s:Project.init(a:project_name)
    call p.Scrape()
    let app = s:Item.init()
    let app.text = app_text
    return p.appointment_list.AddItem(app, 0)
endfunction

function! s:AddCursorItemToSetup() " {{{2
    let current_item = s:Item.GetItemTreeOnLine()
    if current_item.project_name == ''
        let current_item.project_name = s:Project.GetNameFromIndexFile()
    endif
    let setup = s:SetupList.GetSetupForDate()
    if setup.starting_line == -1
        return "echo 'No setup for today yet!'"
    endif
    return setup.AddItem(current_item, 0)
endfunction

function! s:CreateSearchWin(size) " {{{2 Inspired by NERDTree

    if !exists('t:VikiSearchBufName')
        let t:VikiSearchBufName = s:GetNextSearchBuffer()
        silent! exec "botright " . a:size . ' new'
        silent! exec "edit " . t:VikiSearchBufName
    else
        silent! exec "botright " . a:size . ' split'
        silent! exec "buffer " . t:VikiSearchBufName
    endif

    setlocal winfixheight

    "throwaway buffer options
    setlocal noswapfile
    setlocal buftype=nofile
    setlocal nowrap
    setlocal foldcolumn=0
    setlocal nobuflisted
    setlocal nospell

    iabc <buffer>

    setlocal cursorline
    map <buffer> <CR> <Plug>VikiGTDGotoSearchResult
    map <buffer> o <Plug>VikiGTDGotoSearchResult
    map <buffer> <script> <Plug>VikiGTDGotoSearchResult <SID>GotoSearchResult
    map <SID>GotoSearchResult :exe <SID>GotoSearchResult()<CR>
    map <buffer> q :q<CR>
endfunction

function! s:GotoSearchResult()
    let results_line = getline('.')
    let f = matchstr(results_line, '\S\+$')
    if filereadable(f)
        let uw = s:FirstUsableWindow()
        if uw != -1
            return uw . 'wincmd w | e ' . f
        else
            return "wincmd k | rightb vsp " . f
        endif
    endif
endfunction


let s:SearchBufferNr = 0
function! s:GetNextSearchBuffer() " {{{2
    let result = 'VikiGTDSearchBuf' . s:SearchBufferNr
    let s:SearchBufferNr = s:SearchBufferNr + 1
    return result
endfunction

"FUNCTION: s:firstUsableWindow(){{{2 Stolen from NERDTree
"find the window number of the first normal window
function! s:FirstUsableWindow()
    let i = 1
    while i <= winnr("$")
        let bnum = winbufnr(i)
        if bnum != -1 && getbufvar(bnum, '&buftype') ==# ''
                    \ && !getwinvar(i, '&previewwindow')
                    \ && (!getbufvar(bnum, '&modified') || &hidden)
            return i
        endif

        let i += 1
    endwhile
    return -1
endfunction

function! s:SearchVikiGTD(...) " {{{2
    if a:0 == 0
        echo "Please provide search terms"
        return
    endif
    if has("python")
python << EOF
try:
    import xapian
except:
    print "Xapian is not installed."
import sys
import vim
try:
    py_path_additions = vim.eval('g:python_path')
    for addition in py_path_additions[::-1]:
        if addition not in sys.path:
            sys.path.insert(0, addition)
except:
    pass


db_loc = vim.eval('g:vikiGtdDB')
try:
    from viki_search import search_database
    db = xapian.Database(db_loc)
    results = search_database(" ".join(vim.eval("a:000")), db)
    if len(results) == 0:
        results_text = ["No results.",]
    else:
        results_text = ['%d: %i%% %s' % (r.rank + 1, r.percent, r.document.get_value(0)) for r in results]
    vim.command("call s:CreateSearchWin(%d)" % len(results))
    vim.current.buffer.append(results_text)
    vim.command("normal ggdd")
except Exception, e:
    print 'Could not search: Exception is', e
db = None

# print results
EOF
    else
        echo "Python and Xapian must be installed for search."
    endif
endfunction

function! s:IndexThisFile()
    if !exists("b:vikiGtdNeedsIndexing")
        return
    endif
    echo "indexing file"
    if has("python")
python << EOF
try:
    import xapian
except:
    print "Xapian is not installed."
import sys
import vim
try:
    py_path_additions = vim.eval('g:python_path')
    for addition in py_path_additions[::-1]:
        if addition not in sys.path:
            sys.path.insert(0, addition)
except:
    pass
db_loc = vim.eval('g:vikiGtdDB')
try:
    from viki_search import index_file
    db = xapian.WritableDatabase(db_loc, xapian.DB_CREATE_OR_OPEN)
    index_file(vim.eval("expand('%:p')"), db, vim.eval('s:db_psh'))
except Exception, e:
    print 'Could not index file: Exception is', e
db = None
EOF
    else
        echo "Must have python and Xapian installed for search."
    endif
endfunction

function! s:BuildSearchIndex() "{{{2
    if has("python")
python << EOF
try:
    import xapian
except:
    print "Xapian is not installed."
import sys
import vim
try:
    py_path_additions = vim.eval('g:python_path')
    for addition in py_path_additions[::-1]:
        if addition not in sys.path:
            sys.path.insert(0, addition)
except:
    pass
db_loc = vim.eval('g:vikiGtdDB')
try:
    from viki_search import index_directory
    db = xapian.WritableDatabase(db_loc, xapian.DB_CREATE_OR_OPEN)
    index_directory(vim.eval("g:vikiGtdHome"), db, vim.eval('s:db_psh'))
except Exception, e:
    print 'Could not build index: Exception is', e

db = None
EOF
    else
        echo "Must have python and Xapian installed for search."
    endif
endfunction

function! s:UpdateSearchIndex() "{{{2
    if has("python")
python << EOF
try:
    import xapian
except:
    print "Xapian is not installed."
import sys, os
import vim
try:
    py_path_additions = vim.eval('g:python_path')
    for addition in py_path_additions[::-1]:
        if addition not in sys.path:
            sys.path.insert(0, addition)
except:
    pass
db_loc = vim.eval('g:vikiGtdDB')
try:
    from viki_search import update_index
    db = xapian.WritableDatabase(db_loc, xapian.DB_CREATE_OR_OPEN)
    update_index(vim.eval("g:vikiGtdHome"), db, vim.eval('s:db_psh'))
except Exception, e:
    print 'Could not update index: Exception is', e

db = None
EOF
    else
        echo "Must have python and Xapian installed for search."
    endif
endfunction

" Public Functions {{{1

function! VikiGTDGetTodos(filter) "{{{2
    let todo_lists = s:GetItemLists('todo_list')
    let todo_lists = todo_lists.Filter(s:ItemList.FilterByNaturalLanguageDate(a:filter))
    let todo_lists = todo_lists.Sort('s:SortByDate')
    return todo_lists
endfunction

function! b:VikiGTDGetProjectNamesForAutocompletion(...) "{{{2
    let project_names = s:Project.GetProjectNames()
    return join(project_names, "\n")
endfunction

function! b:VikiGTDGetContextsForAutocompletion(...) "{{{2
    let todo_lists = s:GetItemLists('todo_list')
    let contexts = []
    for item in todo_lists.items
        if item.context != '' && index(contexts, item.context) == -1
            call add(contexts, item.context)
        endif
    endfor
    return join(contexts, "\n")
endfunction

function! b:VikiGTDGetContactsForAutocompletion(...) "{{{2
    let todo_lists = s:GetItemLists('todo_list')
    let contacts = []
    for item in todo_lists.items
        if item.contact != '' && index(contacts, item.contact) == -1
            call add(contacts, item.contact)
        endif
    endfor
    return join(contacts, "\n")
endfunction

" Commands Mappings and Highlight Groups {{{1
"
" Autocommands {{{2
if !exists("g:vikiGtdAutoCommandsSet")
    au BufUnload *.viki call <SID>IndexThisFile()
    au BufWritePost *.viki let b:vikiGtdNeedsIndexing = 1
    let g:vikiGtdAutoCommandsSet = 1
endif
"
" Commands {{{2
"
let s:date_ranges = ['', 'Today', 'Tomorrow', 'ThisWeek', 'TodayAndTomorrow', 'Overdue', 'All', 'Undated']
for date_range in s:date_ranges


    if !exists(":PrintTodos" . date_range)
        exe "command PrintTodos" . date_range . " :call s:PrintItems(\"todo_list\", [s:ItemList.FilterByNaturalLanguageDate(\"" . date_range . "\")], \"s:SortByPriorityDate\")"
    endif

    if !exists(":PrintWfs" . date_range)
        exe "command PrintWfs" . date_range . " :call s:PrintItems(\"waiting_for_list\", [s:ItemList.FilterByNaturalLanguageDate(\"" . date_range . "\")], \"s:SortByPriorityDate\")"
    endif

    if !exists(":PrintAppointments" . date_range)
        exe "command PrintAppointments" . date_range . " :call s:PrintItems(\"appointment_list\", [s:ItemList.FilterByNaturalLanguageDate(\"" . date_range . "\")], \"s:SortByPriorityDate\")"
    endif


    if !exists(":Todos" . date_range)
        exe "command Todos" . date_range .  " " . s:OpenItemsInSp("Todos", date_range)
    endif

    if !exists(":Wfs" . date_range)
        exe "command Wfs" . date_range .  " " . s:OpenItemsInSp("Wfs", date_range)
    endif

    if !exists(":Appointments" . date_range)
        exe "command Appointments" . date_range .  " " . s:OpenItemsInSp("Appointments", date_range)
    endif


endfor

if !exists(":PrintTodosByContext")
    command -nargs=1 -complete=custom,b:VikiGTDGetContextsForAutocompletion PrintTodosByContext :call s:PrintItems("todo_list", ["v:val.context == \"" . (<q-args>) . "\""], "s:SortByPriorityDate")
    " command PrintTodosByContext :call s:PrintItems("todo_list", [], "s:SortByContext")
endif

if !exists(":TodosByContext")
    command -nargs=1 -complete=custom,b:VikiGTDGetContextsForAutocompletion TodosByContext :exe s:RunCmdInSp("PrintTodosByContext " . <q-args>)
    " command PrintTodosByContext :call s:PrintItems("todo_list", [], "s:SortByContext")
endif

if !exists(":PrintTodosByContact")
    command -nargs=1 -complete=custom,b:VikiGTDGetContactsForAutocompletion PrintTodosByContact :call s:PrintItems("todo_list", ["v:val.contact == \"" . (<q-args>) . "\""], "s:SortByPriorityDate")
    " command PrintTodosByContact :call s:PrintItems("todo_list", [], "s:SortByContact")
endif

if !exists(":TodosByContact")
    command -nargs=1 -complete=custom,b:VikiGTDGetContactsForAutocompletion TodosByContact :exe s:RunCmdInSp("PrintTodosByContact " . <q-args>)
    " command PrintTodosByContact :call s:PrintItems("todo_list", [], "s:SortByContact")
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

if !exists(":AddAppointment")
    command -nargs=1 -complete=custom,b:VikiGTDGetProjectNamesForAutocompletion AddAppointment :exe s:AddAppointmentCmd(<f-args>)
endif

if !exists(":CopyUndoneTodos")
    command CopyUndoneTodos :call s:CopyUndoneTodos()
endif

if !exists(":SearchVikiGTD")
    command -nargs=? SearchVikiGTD :call s:SearchVikiGTD(<f-args>)
endif

if !exists(":VikiGtdBuildSearchIndex")
    command VikiGtdBuildSearchIndex :call s:BuildSearchIndex()
endif

if !exists(":VikiGtdUpdateSearchIndex")
    command VikiGtdUpdateSearchIndex :call s:UpdateSearchIndex()
endif

" Mappings {{{2

if !hasmapto('<Plug>VikiGTDMarkComplete')
    map <buffer> <unique> <LocalLeader>mc <Plug>VikiGTDMarkComplete
endif
noremap <buffer> <script> <unique> <Plug>VikiGTDMarkComplete <SID>MarkComplete
noremap <SID>MarkComplete :call <SID>MarkItemUnderCursorComplete()<CR>

if !hasmapto('<Plug>VikiGTDGoToProject')
    map <buffer> <unique> <LocalLeader>gp <Plug>VikiGTDGoToProject
endif
noremap <buffer> <script> <unique> <Plug>VikiGTDGoToProject <SID>GoToProject
noremap <SID>GoToProject  :<C-R>=<SID>GoToProject()<CR><CR>

if !hasmapto('<Plug>VikiGTDAddCursorItemToSetup')
    map <buffer> <unique> <LocalLeader>as <Plug>VikiGTDAddCursorItemToSetup
endif
noremap <buffer> <script> <unique> <Plug>VikiGTDAddCursorItemToSetup <SID>AddCursorItemToSetup
noremap <SID>AddCursorItemToSetup  :<C-R>=<SID>AddCursorItemToSetup()<CR><CR>


" Highlight groups {{{1
highlight VikiDate ctermfg=91
call matchadd("VikiDate", '\d\{4\}-\d\{2\}-\d\{2\}')
highlight DueToday ctermfg=Red
call matchadd("DueToday", strftime("%Y-%m-%d"))
highlight DueTomorrow ctermfg=202
call matchadd("DueTomorrow", strftime("%Y-%m-%d", localtime() + 24*60*60))

" priority highlighting
highlight VikiGTDUrgent ctermfg=Red ctermbg=21
highlight VikiGTDImportant ctermfg=Red ctermbg=21
call matchadd("VikiGTDUrgent", '\w\@!!!\w\@!') " wish I could do \<!!\> but ! is not a word character on unix
call matchadd("VikiGTDImportant", '\w\@!#!\w\@!') " wish I could do \<#!\> but ! is not a word character on unix

"context highlighting
highlight VikiGTDContext ctermfg=46
call matchadd("VikiGTDContext", '\w\@<!@\w\+\>')

"contact highlighting
highlight VikiGTDContact ctermfg=200
call matchadd("VikiGTDContact", '\w\@<!&\w\+\>')

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

    function! b:test_project.TestGetNameFromIndexFile() dict
        call self.AssertEquals('Test', s:Project.GetNameFromIndexFile('/whatever/Test.viki'))
        call self.AssertEquals('Test', s:Project.GetNameFromIndexFile('/whatever/Test/Index.viki'))
        call self.AssertEquals('', s:Project.GetNameFromIndexFile('/whatever/Test/Index.other'))
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
    
        let filtered_todos = new_todolist.Filter(s:ItemList.FilterByDate('0000-00-01', '9999-99-99'))
        call self.AssertEquals(10, len(filtered_todos.items))
    
        let filtered_todos = filtered_todos.Filter(s:ItemList.FilterByDate('2010-01-01', '2010-01-31'))
        call self.AssertEquals(7, len(filtered_todos.items))
    
        let filtered_todos = filtered_todos.Filter(s:ItemList.FilterByDate('2010-01-01', '2010-01-03'))
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

    " Get Item List Testing {{{2
    let b:test_get_item_lists = UnitTest.init("TestGetItems")

    function! b:test_get_item_lists.TestNoFilter() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        let all_todos = s:GetItemLists('todo_list', current_dir . '/fixtures/projects')
        echo len(all_todos.items)
    endfunction

    " Filter Testing {{{2
    let b:test_filter = UnitTest.init("TestFilter")

    function! b:test_filter.TestFilterBasic() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        let lines = readfile(current_dir . '/fixtures/testFilter.txt')
        let new_list = s:ItemList.init()
        call new_list.ParseLines(lines)
        let new_list = new_list.Filter('v:val.date != ""')
        call self.AssertEquals(4, len(new_list.items))
    endfunction

    function! b:test_filter.TestFilterLinked() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        let lines = readfile(current_dir . '/fixtures/testFilter.txt')
        let new_list = s:ItemList.init()
        call new_list.ParseLines(lines)
        let new_list.file_name = 'arbitrary'
        let new_list = new_list.Filter('v:val.date != ""').Filter('v:val.context == "@Tamale"')
        call self.AssertEquals(2, len(new_list.items))
        for item in new_list.items
            call self.AssertEquals(1, len(item.children))
        endfor
        call self.AssertEquals('arbitrary', new_list.file_name) " make sure we still have old properties
    endfunction

    function! b:test_filter.TestFilterChildren() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        let lines = readfile(current_dir . '/fixtures/testFilter.txt')
        let new_list = s:ItemList.init()
        call new_list.ParseLines(lines)
        let new_list = new_list.Filter('v:val.date != "" && v:val.context == "@Tamale"', 1)
        call self.AssertEquals(2, len(new_list.items))
        for item in new_list.items
            call self.AssertEquals(0, len(item.children))
        endfor
    endfunction

    function! b:test_filter.TestFilterNested() dict
        let current_dir = s:Utils.GetCurrentDirectory()
        let lines = readfile(current_dir . '/fixtures/testFilter.txt')
        let new_list = s:ItemList.init()
        call new_list.ParseLines(lines)
        let new_list = new_list.Filter('v:val.context == "@bole"', 1)
        call self.AssertEquals(1, len(new_list.items))
    endfunction

    let b:test_sorting = UnitTest.init("TestSorting")

    function! b:test_sorting.TestContextSort() dict
        call s:Sorter.reset()
        call s:Sorter.AddSortFunction(s:Sorter.SortByContext)
        let l = ['zoo', 'yak', 'was', 'house', 'fire', 'apple']
        call sort(l, 's:SorterSort')
        call self.AssertEquals(['apple', 'fire', 'house', 'was', 'yak', 'zoo'], l)
    endfunction

    function! b:test_sorting.TestComplicateSort() dict
        call s:Sorter.reset()
        call s:Sorter.AddSortFunction(s:Sorter.SortByContext)
        call s:Sorter.AddSortFunction(s:Sorter.SortByDate)
        let firts = {'context': 'apple', 'date': '2010-10-01'}
        let second = {'context': 'beets', 'date':'2010-11-01'}
        let third = {'context': 'beets', 'date': '2010-11-02'}
        let fourth = {'context': 'beets', 'date': ''}
        let fifth = {'context': 'clouds', 'date': '2010-09-04'}
        let sixth = {'context': '', 'date': '2010-07-04'}
        let l = [third, second, fourth, fifth, sixth, firts]
        call sort(l, 's:SorterSort')
        call self.AssertEquals([firts, second, third, fourth, fifth, sixth], l)
    endfunction


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
    call b:test_all.AddUnitTest(b:test_filter)
    call b:test_all.AddUnitTest(b:test_sorting)
    
    " Add objects to FunctionRegister {{{2
    call FunctionRegister.AddObject(s:Utils, 'Utils')
    call FunctionRegister.AddObject(s:Todo, 'Todo')
    call FunctionRegister.AddObject(s:TodoList, 'Todolist')
    call FunctionRegister.AddObject(s:Project, 'Project')
endif

" resetting cpo option
let &cpo = s:save_cpo
" vim: foldmethod=marker
