#!/usr/bin/env python3
"""Read-only capability/accuracy comparison against macOS libsqlite3."""
import ctypes as C
import json
from pathlib import Path
from epub_probe import ASSETS, ROOT

lib=C.CDLL('/usr/lib/libsqlite3.dylib')
lib.sqlite3_libversion.restype=C.c_char_p
lib.sqlite3_open.argtypes=[C.c_char_p,C.POINTER(C.c_void_p)]
lib.sqlite3_close.argtypes=[C.c_void_p]
CALLBACK=C.CFUNCTYPE(C.c_int,C.c_void_p,C.c_int,C.POINTER(C.c_char_p),C.POINTER(C.c_char_p))
lib.sqlite3_exec.argtypes=[C.c_void_p,C.c_char_p,CALLBACK,C.c_void_p,C.POINTER(C.c_char_p)]
db=C.c_void_p();assert lib.sqlite3_open(b':memory:',C.byref(db))==0

def execute(sql):
    rows=[]
    @CALLBACK
    def callback(_,size,values,names):
        rows.append([values[i].decode('utf-8') if values[i] else None for i in range(size)]);return 0
    error=C.c_char_p();status=lib.sqlite3_exec(db,sql.encode('utf-8'),callback,None,C.byref(error))
    if status: raise RuntimeError('native_sqlite_statement_failed')
    return rows

def literal(text):return "'"+text.replace("'","''")+"'"
try:
    source=json.loads((ASSETS/'fixture.json').read_text())
    rows=[(d['id']+'/'+b['id'],b['text']) for d in source['spine'] for b in d['blocks']]
    execute('CREATE TABLE blocks(id TEXT,body TEXT)')
    for id_,text in rows:execute(f'INSERT INTO blocks VALUES ({literal(id_)},{literal(text)})')
    modes={};checks=[]
    for name,tokenizer in [('unicode61','unicode61 remove_diacritics 0'),('trigram','trigram case_sensitive 1')]:
        try:
            execute(f'CREATE VIRTUAL TABLE {name} USING fts5(id UNINDEXED,body,tokenize={literal(tokenizer)})')
            execute(f'INSERT INTO {name} SELECT * FROM blocks');modes[name]=True
        except RuntimeError:modes[name]=False
    for query in ['山','山间','山间来信','山間來信','100%_','📖','e\u0301','，','不存在词']:
        exact=[r[0] for r in execute(f'SELECT id FROM blocks WHERE instr(body,{literal(query)})>0')]
        item={'query':query,'instr':exact,'literal_exact':set(exact)=={id_ for id_,text in rows if query in text}}
        for mode,available in modes.items():
            if available:item[mode]=[r[0] for r in execute(f'SELECT id FROM {mode} WHERE body MATCH {literal(chr(34)+query.replace(chr(34),chr(34)*2)+chr(34))}')]
        checks.append(item)
    result={'engine':'macOS system libsqlite3 via C API','sqlite_version':lib.sqlite3_libversion().decode(),'fts_compile_options':[r[0] for r in execute('PRAGMA compile_options') if 'FTS' in r[0]],'tokenizers':modes,'checks':checks,'all_literal_checks_passed':all(c['literal_exact'] for c in checks),'scope':'capability/accuracy only; no Flutter FFI binding selected or benchmark claim'}
    (ROOT/'docs/verifications/mac-06/search-native-sqlite.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(result['sqlite_version'],modes,'all exact checks:',result['all_literal_checks_passed'])
finally:lib.sqlite3_close(db)
