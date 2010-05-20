import unittest, datetime

from models import ToDo

class TestParseRawText(unittest.TestCase):
    def testSimpleCase(self):
        sample_text = "A simple todo with some simple text."
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, sample_text)
    def testWithLineBreaks(self):
        sample_text = """
Some text with
a line break."""
        no_breaks = "Some text with a line break."
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, no_breaks)
    def testWithLineBreakAndTrailingSpace(self):
        sample_text = """
Some text with a trailing space and 
a line break."""
        no_breaks = "Some text with a trailing space and a line break."
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, no_breaks)
    def testWithDate(self):
        sample_text = "A to do item with a date 2010-05-20"
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, sample_text)
        self.assertEquals(todo.due_date, datetime.date(2010, 5, 20))
    def testIgnoreImproperDate(self):
        sample_text = "A to do item with a date 2010-13-20"
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, sample_text)
        self.assertEquals(todo.due_date, None)
    def testWithLeadingBulletCharacter(self):
        sample_text = " @ A simple todo with some simple text."
        stripped_text = "A simple todo with some simple text."
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, stripped_text)
        sample_text = " # A simple todo with some simple text."
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, stripped_text)
        sample_text = " - A simple todo with some simple text."
        todo = ToDo(sample_text)
        self.assertEquals(todo.text, stripped_text)



if __name__ == '__main__':
    unittest.main()
