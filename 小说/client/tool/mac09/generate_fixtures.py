"""Owned neutral Chinese/emoji long-flow fixtures, reproducible zip metadata."""
from pathlib import Path
import zipfile, hashlib, json
root=Path(__file__).resolve().parents[4]
out=root/'fixtures/novel/mac09'
out.mkdir(exist_ok=True)
paragraphs=[f'第{i:03d}段，山路上的微光。简体中文與繁體文字一起前行，📖与🌿仍保留原来的位置。'+ '溪水沿着石阶流向远处，读到这里也可以停一停。'*4 for i in range(1,121)]
(out/'山路排版.txt').write_text('\n\n'.join(['第一章 山路微光',*paragraphs[:60],'第二章 溪畔来信',*paragraphs[60:]])+'\n',encoding='utf8')
files={
'mimetype':'application/epub+zip',
'META-INF/container.xml':'<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
'book.opf':'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">owned-mac09-v1</dc:identifier><dc:title>山路排版检查</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>',
'nav.xhtml':'<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="one.xhtml">第一章 山路微光</a></li><li><a href="two.xhtml">第二章 溪畔来信</a></li></ol></nav></body></html>'}
for name,title,items in [('one','第一章 山路微光',paragraphs[:60]),('two','第二章 溪畔来信',paragraphs[60:])]:
 files[name+'.xhtml']='<html xmlns="http://www.w3.org/1999/xhtml"><head><title>'+title+'</title></head><body><h1>'+title+'</h1>'+''.join(f'<p id="p{i}">{text}</p>' for i,text in enumerate(items))+'</body></html>'
with zipfile.ZipFile(out/'山路排版.epub','w') as z:
 for name,data in files.items():
  info=zipfile.ZipInfo(name,(2026,10,23,0,0,0));info.compress_type=zipfile.ZIP_STORED if name=='mimetype' else zipfile.ZIP_DEFLATED
  z.writestr(info,data.encode())
(out/'manifest.json').write_text(json.dumps({'version':1,'date':'2026-10-23','rights':'Project-authored neutral text; repository testing and app QA permitted. No external book content.','files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.iterdir()) if p.suffix in ('.txt','.epub')}},ensure_ascii=False,indent=2)+'\n')

asset=root/"小说/client/assets/mac09/flow.epub"
asset.parent.mkdir(exist_ok=True)
asset.write_bytes((out/"山路排版.epub").read_bytes())
