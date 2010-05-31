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

" Object Definitions {{{1
"
" Class: Utils {{{2
"
let s:Utils = {}
function! s:Utils.GetCurrentDirectory() dict
    let current_buf = expand("%:p")
    let split_path = split(current_buf, '/')
    let current_dir = '/'.join(remove(split_path, 0, -2), '/')
    return current_dir
endfunction

function! s:Utils.LineIndent(line) dict
    " Not that this currently counts tabs as 1. Don't use tabs! :)
    return strlen(matchstr(a:line, '^\s*'))
endfunction

" Class: Todo {{{2
"
let s:Todo = {}
function! s:Todo.init() dict
    let ret_val = copy(self)
    let ret_val.text = ""
    let ret_val.date = ""
    return ret_val
endfunction

function! s:Todo.ParseLines(lines) dict
    let first_line = remove(a:lines, 0)
    if match(first_line, '^\s*[@-] ') == -1
        throw "vikiGTDError: Todo item is improperly constructed - first line does not start with a bullet point character (@ or -)."
    endif
    let self.text = substitute(first_line, '^\s*[@-] ', '', '')
    for line in a:lines
        if match(line, '^\s*[@-] ') != -1
            throw "vikiGTDError: Todo item is improperly constructed - additional starts with a bullet point character (@ or -)."
        endif
       let stripped_line = substitute(line, '^\s*', '', '')
       let self.text = self.text . stripped_line
    endfor
endfunction

" Class: TodoList {{{2

let s:TodoList = {}

function! s:TodoList.init() dict
    let ret_val = copy(self)
    let ret_val.todos = []
    return ret_val
endfunction

function! s:TodoList.AddTodo(lines) dict
    if a:lines != []
        let new_todo = s:Todo.init()
        call new_todo.ParseLines(a:lines)
        call add(self.todos, new_todo)
    endif
endfunction

function! s:TodoList.ParseLines(lines) dict
    let lines_for_todo = []
    " remove lines before the ** Todo
    while match(a:lines[0], '^\*\*\s*Todo') == -1
        call remove(a:lines, 0)
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
            " here we are at a new todo item, so add the old one
            call self.AddTodo(lines_for_todo)
            let lines_for_todo = []
        endif
        call add(lines_for_todo, line)
        let last_line_indent = line_indent
    endfor
    " parse the final todo item after all lines have been gone through
    call self.AddTodo(lines_for_todo)
endfunction
" }}}
" Tests {{{1
" Test Todo {{{2
let b:test_todo = copy(UnitTest)
let b:test_todo.name = "TestTodo"

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

let b:test_todolist = copy(UnitTest)
let b:test_todolist.name = "TestTodoList"

function! b:test_todolist.TestParseFile() dict
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

function! b:test_todolist.TestTougherFile() dict
    let current_dir = s:Utils.GetCurrentDirectory()
    let test_file = current_dir . '/fixtures/tougherTodo.txt'
    let lines = readfile(current_dir . '/fixtures/tougherTodo.txt')
    let new_todolist = s:TodoList.init()
    call new_todolist.ParseLines(lines)
    call self.AssertEquals(len(new_todolist.todos), 6, "TodoList should have three items.")
endfunction

let b:test_utils = copy(UnitTest)
let b:test_utils.name = "TestUtils"
function! b:test_utils.TestGetDirectory() dict
    let current_dir = s:Utils.GetCurrentDirectory()
    call self.AssertEquals(current_dir, '/home/benjamin/Code/vimscripts/viki_gtd/ftplugin', 'current_dir and path should be equal.') " Change this path when script is installed!
endfunction

function! b:test_utils.TestLineIndent() dict
    call self.AssertEquals(s:Utils.LineIndent("    Four spaces."), 4, "Four spaces should return an indent of 4")
    call self.AssertEquals(s:Utils.LineIndent("No spaces"), 0, "No spaces should return an indent of 0")
    call self.AssertEquals(s:Utils.LineIndent("\tA tab!"), 1, "A tab should return an indent of 1")
endfunction

function! b:TestAll()
    call b:test_todo.RunTests()
    call b:test_todolist.RunTests()
    call b:test_utils.RunTests()
endfunction

" Add objects to FunctionRegister
call FunctionRegister.AddObject(s:Utils, 'Utils')
call FunctionRegister.AddObject(s:Todo, 'Todo')
call FunctionRegister.AddObject(s:TodoList, 'Todolist')

" resetting cpo option
let &cpo = s:save_cpo
" vim: foldmethod=marker
