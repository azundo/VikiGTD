import os, sys
import shelve
import xapian


def index_file(name, database, shelf):
    indexer = xapian.TermGenerator()
    stemmer = xapian.Stem("english")
    indexer.set_stemmer(stemmer)
    d = shelve.open(shelf)
    if not os.path.isfile(name):
        return
    try:
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
        d[name] = os.path.getmtime(name)
        f = None
    except:
        pass
    d.close()

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
    return files

def index_directory(directory, database, shelf):
    files = crawl_directory(directory)
    for f in files:
        index_file(f, database, shelf)

def update_index(directory, database, shelf):
    files = crawl_directory(directory)
    d = shelve.open(shelf)
    files_to_index = [f for f in files if d.get(f, None) != os.path.getmtime(f)]
    d.close()
    for f in files_to_index:
        print 'Updating %s in index.' % f
        index_file(f, database, shelf)

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
    return results
