import os, sys
import xapian

def index_file(file_name, database):
    indexer = xapian.TermGenerator()
    stemmer = xapian.Stem("english")
    indexer.set_stemmer(stemmer)
    f = open(name)
    content = ''
    for line in f:
        content += line.strip() + ' '
    doc = xapian.Document()
    doc.set_data(content)
    doc.add_value(0, name)
    indexer.set_document(doc)
    indexer.index_text(content)
    doc.add_term(name)
    database.replace_document(name, doc)
    f = None

def crawl_directory(directory):
    contents = [os.path.join(directory, item) 
            for item in os.listdir(directory) if
            item[0] != '.']
    dirs = [item for item in contents if 
            os.path.isdir(item)]
    files = [item for item in contents if 
            os.path.isfile(item)]
    for dir in dirs:
        files += crawl_directory(dir)

def index_directory(directory, database):
    files = crawl_directory(index_directory)
    for f in files:
        index_file(f, database)

def search_database(query_string, database):
    enquire = xapian.Enquire(database)
    qp = xapian.QueryParser()
    stemmer = xapian.Stem("english")
    qp.set_stemmer(stemmer)
    qp.set_database(database)
    qp.set_stemming_strategy(xapian.QueryParser.STEM_SOME)
    q = qp.parse_query(query_string)
    enquire.set_query(q)
    results = enquire.get_mset(0, 10)
    results_text = '\n'.join(['%d: %i%% %s' % (r.rank + 1, r.percent, r.document.get_value(0)) for r in results])
    return results_text
