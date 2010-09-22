if !exists('loaded_snippet') || &cp
    finish
endif

function! s:GetSundayForWeek(weektime)
    let offset = str2nr(strftime("%w", a:weektime))
    return a:weektime - (offset * 24 * 60 * 60)
endfunction

function! s:GetDateForDayName(dayname)
    let today = localtime()
    let sunday = s:GetSundayForWeek(today)
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
    return strftime("%Y-%m-%d", sunday + (onset * 24 * 60 * 60))
endfunction

" function! GetFirstSundayOfMonth()
"     let today = localtime()
"     let month = str2num(strftime('%m'))
"     let sunday = s:GetSundayForWeek(today)
"     while 
" 
" endfunction

let st = g:snip_start_tag
let et = g:snip_end_tag
let cd = g:snip_elem_delim

exec "Snippet day * ".st."date".et."
\<CR>
\<CR>** Daily Habits
\<CR>
\<CR><TAB>@ Do daily set up first thing
\<CR><TAB>@ Review Todos and Overdue Todos
\<CR>@ Review Daily Projects
\<CR><BS>@ Blog for half an hour
\<CR>
\<CR><BS>** Appointments
\<CR>
\<CR>** Set up
\<CR>
\<CR>** Waiting For
\<CR>
\<CR>** Reflections/Notes"

exec "Snippet today * ".strftime("%Y-%m-%d")."
\<CR>** Daily Habits
\<CR>
\<CR><TAB>@ Do daily set up first thing
\<CR><TAB>@ Review Todos and Overdue Todos
\<CR>@ Review Daily Projects
\<CR><BS>@ Blog for half an hour
\<CR>
\<CR><BS>** Appointments
\<CR>
\<CR>** Set up
\<CR>
\<CR>** Waiting For
\<CR>
\<CR>** Reflections/Notes"

exec "Snippet week * Week of ".st."date".et."
\<CR>
\<CR>** Weekly Habits
\<CR><TAB>@ Beginning of Week Reflection
\<CR>@ Review Weekly and Daily Projects
\<CR>@ Mid Week Check-In
\<CR>@ Blog Post
\<CR>@ Exercise Quota
\<CR>@ Email Under Control
\<CR>
\<CR><BS>** Beginning of Week Reflection and Prep
\<CR>".st.et."
\<CR>
\<CR>** Mid-Week Check-in
\<CR>
\<CR>** Exercise Record
\<CR>
\<CR>** Days
\<CR><TAB>@ Sunday: 
\<CR>@ Monday: 
\<CR>@ Tuesday: 
\<CR>@ Wednesday: 
\<CR>@ Thursday: 
\<CR>@ Friday: 
\<CR>@ Saturday:"

exec "Snippet thisweek * Week of ".s:GetDateForDayName("Sunday")."
\<CR>
\<CR>** Weekly Habits
\<CR><TAB>@ Beginning of Week Reflection
\<CR>@ Review Weekly and Daily Projects
\<CR>@ Mid Week Check-In
\<CR>@ Blog Post
\<CR>@ Exercise Quota
\<CR>@ Email Under Control
\<CR>
\<CR><BS>** Beginning of Week Reflection and Prep
\<CR>".st.et."
\<CR>
\<CR>** Mid-Week Check-in
\<CR>
\<CR>** Exercise Record
\<CR>
\<CR>** Days
\<CR><TAB>@ Sunday: [[days/".s:GetDateForDayName("Sunday")."]]
\<CR>@ Monday: [[days/".s:GetDateForDayName("Monday")."]]
\<CR>@ Tuesday: [[days/".s:GetDateForDayName("Tuesday")."]]
\<CR>@ Wednesday: [[days/".s:GetDateForDayName("Wednesday")."]]
\<CR>@ Thursday: [[days/".s:GetDateForDayName("Thursday")."]]
\<CR>@ Friday: [[days/".s:GetDateForDayName("Friday")."]]
\<CR>@ Saturday: [[days/".s:GetDateForDayName("Saturday")."]]"

exec "Snippet month * ".st."date".et."
\<CR>
\<CR>** Monthly Habits
\<CR><TAB>@ Monthly Goals
\<CR>@ Update of APS Competencies
\<CR>
\<CR><BS>** Weeks
\<CR><TAB>@ Week 1: ".st.et."
\<CR>@ Week 2: 
\<CR>@ Week 3: 
\<CR>@ Week 4: 
\<CR>@ (Week 5:) "

" id stands for insert date - insert the current date formatted in the proper
" style. Nice when you want to add a date timestamp to new files.
exec "Snippet id ".strftime("%Y-%m-%d").st.et
