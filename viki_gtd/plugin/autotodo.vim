function! TransferTodoToToday()
python << EOF
import vim, os, datetime
def transfer_current_line():
    print vim.current.line
    today = datetime.date.today()
    path_to_today = '/home/benjamin/Wikis/habits/weeks/days/%d-%d-%d.viki' % (today.year, today.month, today.day)

EOF
endfunction
