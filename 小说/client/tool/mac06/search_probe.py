#!/usr/bin/env python3
"""Local exact Chinese search experiment; no production database migration."""
import json, statistics, sqlite3, time
from pathlib import Path
from epub_probe import ASSETS, ROOT, utf16len

def quote_fts(text): return '"'+text.replace('"','""')+'"'
def measure(call, repeats=15):
    samples=[]; result=None
    for _ in range(repeats):
        started=time.perf_counter();result=call();samples.append((time.perf_counter()-started)*1000)
    samples.sort();return {'p50_ms':round(statistics.median(samples),3),'p95_ms':round(samples[int((len(samples)-1)*.95)],3),'hits':len(result)}

def run():
    value=json.loads((ASSETS/'fixture.json').read_text())
    rows=[(f'{doc["id"]}/{block["id"]}',block['text']) for doc in value['spine'] for block in doc['blocks']]
    rows += [('trad','只有繁體山間來信'),('nfc','预组 é 与组合 e\u0301 不自动合并'),('literal','100%_完成，字面 OR "NOT"，📖。'),('false','山谷间的信，不是连续词')]
    db=sqlite3.connect(':memory:')
    db.execute('CREATE TABLE blocks(id TEXT PRIMARY KEY, body TEXT NOT NULL)')
    db.executemany('INSERT INTO blocks VALUES (?,?)',rows)
    tokenizer_results={}
    for name,spec in [('unicode61','unicode61 remove_diacritics 0'),('trigram','trigram case_sensitive 1')]:
        try:
            db.execute(f"CREATE VIRTUAL TABLE {name} USING fts5(id UNINDEXED, body, tokenize='{spec}')")
            db.executemany(f'INSERT INTO {name} VALUES (?,?)',rows)
            tokenizer_results[name]={'available':True}
        except sqlite3.OperationalError as error: tokenizer_results[name]={'available':False,'error_class':type(error).__name__}
    checks=[]
    for query in ['山','山间','山间来信','山間來信','100%_','📖','e\u0301','é','，','OR "NOT"','不存在词']:
        expected=[id_ for id_,text in rows if query in text]
        exact=[row[0] for row in db.execute('SELECT id FROM blocks WHERE instr(body,?)>0',(query,))]
        item={'query':query,'expected':expected,'instr':exact,'instr_exact':set(expected)==set(exact)}
        for tokenizer in tokenizer_results:
            if not tokenizer_results[tokenizer]['available']:continue
            actual=[row[0] for row in db.execute(f'SELECT id FROM {tokenizer} WHERE body MATCH ?',(quote_fts(query),))]
            item[tokenizer]=actual
        if len(query)<3 or not tokenizer_results['trigram']['available']: candidates=exact;strategy='bounded_substring'
        else:
            ids=item['trigram']; candidates=[id_ for id_,text in rows if id_ in ids and query in text];strategy='trigram_plus_exact_verification'
        item['selected_strategy']=strategy;item['selected_exact']=set(candidates)==set(expected)
        checks.append(item)
    position=[]
    for doc in value['spine']:
        for block in doc['blocks']:
            if block['id']=='target':
                text=block['text'];word='目标位置';index=text.index(word)
                sql_scalar=db.execute('SELECT instr(body,?) FROM blocks WHERE id=?',(word,doc['id']+'/'+block['id'])).fetchone()[0]-1
                position.append({'block':block['id'],'sql_unicode_scalar_offset':sql_scalar,'utf16_offset':utf16len(text[:index]),'utf16_length':utf16len(word),'prefix':text[:index]})
    # A generated ~5MiB corpus stays local under ignored build/.
    folder=ROOT/'小说/client/build/mac06';folder.mkdir(parents=True,exist_ok=True)
    bench=folder/'search-benchmark.sqlite';bench.unlink(missing_ok=True)
    b=sqlite3.connect(bench);b.execute('CREATE TABLE blocks(id INTEGER PRIMARY KEY, body TEXT NOT NULL)')
    corpus=[(i, f'第{i}段。'+('山路的风带来清晨消息。'*12)+('唯一目标词' if i==321 else '雨后继续走。')) for i in range(10000)]
    b.executemany('INSERT INTO blocks VALUES (?,?)',corpus);b.commit()
    t=time.perf_counter();b.execute("CREATE VIRTUAL TABLE tri USING fts5(id UNINDEXED, body, tokenize='trigram case_sensitive 1')");b.executemany('INSERT INTO tri VALUES (?,?)',corpus);b.commit();build=time.perf_counter()-t
    metrics={}
    for q in ['山','山路','唯一目标词','不存在词','📖']:
        metrics[q]={'instr':measure(lambda: b.execute('SELECT id FROM blocks WHERE instr(body,?)>0 LIMIT 50',(q,)).fetchall())}
        if len(q)>=3:metrics[q]['trigram_verified']=measure(lambda: b.execute('SELECT b.id FROM tri t JOIN blocks b ON b.id=t.id WHERE tri MATCH ? AND instr(b.body,?)>0 LIMIT 50',(quote_fts(q),q)).fetchall())
    result={'sqlite_version':sqlite3.sqlite_version,'fts_compile_options':[row[0] for row in db.execute('PRAGMA compile_options') if 'FTS' in row[0]],'tokenizers':tokenizer_results,'accuracy':checks,'anchor_offsets':position,'benchmark':{'paragraphs':len(corpus),'utf8_bytes':sum(len(t.encode()) for _,t in corpus),'database_bytes':bench.stat().st_size,'fts_build_seconds':round(build,3),'latency':metrics},'all_selected_checks_passed':all(c['selected_exact'] for c in checks),'limitations':['Python SQLite is a research runtime; rerun against the exact MAC-03 Flutter SQLite build','short queries use bounded substring scan, not accelerated FTS','no simplified/traditional automatic conversion or normalization of original IDs/text','LIMIT 50 is a probe bound, not final pagination/cancellation implementation']}
    out=ROOT/'docs/verifications/mac-06/search.json';out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    assert result['all_selected_checks_passed']
    print(f'Search: {len(checks)} exact checks passed; SQLite {sqlite3.sqlite_version}; corpus {result["benchmark"]["utf8_bytes"]} bytes')
if __name__=='__main__':run()
