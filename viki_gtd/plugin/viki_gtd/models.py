# defines python models useful for viki_gtd stuff

import re, datetime

class ToDo(object):

    def __init__(self, raw_text):
        """ Parses the raw text input in order to fill in any properties of the
        ToDo item."""
        # removes leading bullet characters
        raw_text = raw_text.strip().strip('@#- ')
        lines = raw_text.split('\n')
        # removes blank lines and strips any trailing or 
        # leading spaces from lines
        self.text = ' '.join([line.strip() for line in lines if line])
        self.due_date = None

        # see if there is a date in the text, if so, add it as the due date
        date_re = re.compile(r'(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})')
        match = date_re.search(self.text)
        if match:
            date_values = match.groups()
            try:
                due_date = datetime.date(int(date_values[0]), int(date_values[1]), int(date_values[2]))
                self.due_date = due_date
            except ValueError:
                pass
