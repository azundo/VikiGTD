" The plugin for viki files to allow me to seriously get stuff done! {{{1
"
"
"
"
" Some general niceties
" Leave this out for now so I can easily source file
" if exists('b:loaded_viki_gtd')
"     finish
" endif
let b:loaded_viki_gtd = 1

let s:save_cpo = &cpo
set cpo&vim " set this to allow linecontinuations. cpo is reset at the end

" Global var definitions {{{1
"
if !exists("g:vikiGtdProjectsDir")
    let g:vikiGtdProjectsDir = $HOME.'/Wikis/projects'
endif

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

" Class: Todo {{{2
"
let s:Todo = {}
function! s:Todo.init() dict "{{{3
    let instance = copy(self)
    let instance.text = ""
    let instance.date = ""
    let instance.parent = {}
    let instance.children = []
    return instance
endfunction

function! s:Todo.ParseLines(lines) dict "{{{3
    let first_line = remove(a:lines, 0)
    if match(first_line, '^\s*[@-] ') == -1
        throw "vikiGTDError: Todo item is improperly constructed - first line does not start with a bullet point character (@ or -)."
    endif
    let self.text = substitute(first_line, '^\s*[@-] ', '', '')
    let self.text = substitute(self.text, '\s*$', '', '')
    for line in a:lines
        if match(line, '^\s*[@-] ') != -1
            throw "vikiGTDError: Todo item is improperly constructed - additional starts with a bullet point character (@ or -)."
        endif
       let stripped_line = substitute(substitute(line, '^\s*', '', ''), '\s*$', '', '')
       let self.text = self.text . ' ' . stripped_line
    endfor
    let self.date = matchstr(self.text, '\d\{4\}-\d\{2\}-\d\{2\}')
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
    return join(lines, "\n")
endfunction

" Class: TodoList {{{2

let s:TodoList = {}

function! s:TodoList.init() dict "{{{3
    let instance = copy(self)
    let instance.todos = []
    return instance
endfunction

function! s:TodoList.AddTodo(lines, ...) dict "{{{3
    if a:lines != []
        let new_todo = s:Todo.init()
        call new_todo.ParseLines(a:lines)
        call add(self.todos, new_todo)
        if a:0 > 0
            let new_todo.parent = a:1
            if has_key(a:1, 'children')
                call add(a:1['children'], new_todo)
            endif
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
    endwhile
    " Remove the **Todo line
    call remove(a:lines, 0)
    let last_line_indent = -1
    for line in a:lines
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
            let new_todo = self.AddTodo(lines_for_todo, parent_stack[0])
            let lines_for_todo = []
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
    call self.AddTodo(lines_for_todo)
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
            call add(lines, t.Print(4, a:1))
        endfor
    else
        for t in self.todos
            call add(lines, t.Print(4))
        endfor
    endif
    return join(lines, "\n")
endfunction

" Functions {{{1
"
"
function! s:ScrapeProjectDir(directory) " {{{2
    let index_files = findfile('Index.viki', a:directory.'/**/*', -1)
    let standalone_projects = split(globpath(a:directory, '*.viki'), '\n')
    " remove the projects/Index.viki
    call filter(standalone_projects, 'v:val !~ "Index.viki"')
    " Add the files together
    let index_files = extend(index_files, standalone_projects)
    let todo_lists = []
    for filename in index_files
        let new_list = s:TodoList.init()
        call new_list.ParseLines(readfile(filename))
        call add(todo_lists, new_list)
    endfor
    return todo_lists
endfunction

function! s:CombineTodoLists(lists) "{{{2
    let combined_list = s:TodoList.init()
    for l in a:lists
        call extend(combined_list.todos, l.todos)
    endfor
    return combined_list
endfunction

function! s:PrintTodos(filter) "{{{2
    let all_todo_lists = s:ScrapeProjectDir(g:vikiGtdProjectsDir)
    let all_todos_list = s:CombineTodoLists(all_todo_lists)
    if a:filter == 'today'
        let filtered_todos = all_todos_list.GetDueToday()
    elseif a:filter == 'todayandtomorrow'
        let filtered_todos = all_todos_list.GetDueTodayOrTomorrow()
    elseif a:filter == 'tomorrow'
        let filtered_todos = all_todos_list.GetDueTomorrow()
    else
        return
    endif
    let split_todos = split(filtered_todos.Print(1), "\n")
    call append(line('.'), split_todos)
    exe "normal V".len(split_todos)."jgq"
endfunction

" Commands {{{1
if !exists(":PrintTodaysTodos")
    command PrintTodaysTodos :call s:PrintTodos('today')
endif

if !exists(":PrintTomorrowsTodos")
    command PrintTomorrowsTodos :call s:PrintTodos('tomorrow')
endif

if !exists(":PrintTodaysAndTomorrowsTodos")
    command PrintTodaysAndTomorrowsTodos :call s:PrintTodos('todayandtomorrow')
endif

" Highlight groups {{{1
highlight DueToday ctermbg=Green
call matchadd("DueToday", strftime("%Y-%m-%d"))
highlight DueTomorrow ctermbg=LightBlue
call matchadd("DueTomorrow", strftime("%Y-%m-%d", localtime() + 24*60*60))

" Tests {{{1
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
    call self.AssertEquals(new_todolist.todos[1].text, "Another random item that is longer than a single line of text so we can parse this one properly", "Second todo item.")
    call self.AssertEquals(new_todolist.todos[2].text, "Somthing here", "Third todo item.")
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
    call self.AssertEquals(current_dir, '/home/benjamin/Code/vimscripts/viki_gtd/ftplugin', 'current_dir and path should be equal.') " Change this path when script is installed!
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
    call self.AssertEquals(len(todolists), 4)
endfunction

" Easy function for testing all {{{2
function! b:TestAll()
    call b:test_todo.RunTests()
    call b:test_todolist.RunTests()
    call b:test_utils.RunTests()
    call b:test_scrape.RunTests()
endfunction

" Add objects to FunctionRegister {{{1
call FunctionRegister.AddObject(s:Utils, 'Utils')
call FunctionRegister.AddObject(s:Todo, 'Todo')
call FunctionRegister.AddObject(s:TodoList, 'Todolist')

" resetting cpo option
let &cpo = s:save_cpo
" vim: foldmethod=marker
