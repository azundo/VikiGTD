" The plugin for viki files to allow me to seriously get stuff done!
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

" TESTS! 1}}}
let b:TestParseTodos = copy(UnitTest)
let b:TestParseTodos.name = "TestParseTodos"
function! b:TestParseTodos.TestIdentifyTodoList() dict
    call self.AssertTrue(TRUE(), 'Simple truth test to see if things are working.')
    let parser = copy(s:TodoParser)
endfunction

" resetting cpo option
let &cpo = s:save_cpo
