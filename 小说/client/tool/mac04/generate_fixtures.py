"""Owned, neutral Chinese import cases; no public content or user documents."""
import hashlib,json,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'fixtures/novel/mac04'
OUT.mkdir(parents=True,exist_ok=True)
texts={'简体':'第一章 山间来信\n\n这是自产的中文导入样本。窗外下过一阵小雨。📖\n', '繁體':'第一章 山間來信\n\n這是自產的中文匯入樣本。窗外下過一陣小雨。\n'}
for name,enc,text in [('简体-utf8.txt','utf-8',texts['简体']),('BOM-utf8.txt','utf-8-sig',texts['简体']),('UTF16LE.txt','utf-16',texts['简体']),('UTF16BE.txt','utf-16-be',texts['繁體']),('GB18030.txt','gb18030',texts['简体']),('Big5.txt','big5',texts['繁體'])]:
 (OUT/name).write_bytes(text.encode(enc))
(OUT/'错误编码.txt').write_bytes(b'\xff\x81\x00\xfe')
(OUT/'坏包.epub').write_bytes(b'PK\x03\x04not-a-book')
(OUT/'同名A.txt').write_text('同名测试甲，正文不同。\n')
(OUT/'同名B.txt').write_text('同名测试乙，正文不同。\n')
container='<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
opf='<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>自产导入试验</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>'
base={'mimetype':b'application/epub+zip','META-INF/container.xml':container.encode(),'OEBPS/content.opf':opf.encode(),'OEBPS/chapter.xhtml':'<html xmlns="http://www.w3.org/1999/xhtml"><body><p>自产的中性导入样本。</p></body></html>'.encode()}
for filename,extra in [('有效.epub',{}),('路径穿越.epub',{'../outside.txt':b'no'}),('加密标记.epub',{'META-INF/encryption.xml':b'<encryption/>'}),('外部实体.epub',{'META-INF/container.xml':b'<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><x>&e;</x>'}),('展开超限.epub',{'huge.bin':b'0'*(17*1024*1024)})]:
 with zipfile.ZipFile(OUT/filename,'w') as archive:
  for name,value in (base|extra).items():
   info=zipfile.ZipInfo(name,(2026,10,20,0,0,0));info.compress_type=zipfile.ZIP_STORED if name=='mimetype' else zipfile.ZIP_DEFLATED
   archive.writestr(info,value)
manifest={'date':'2026-10-20','provenance':'Project-owned neutral fixture text and generated archives; no adult body or external assets.', 'files':[{ 'name':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUT.iterdir()) if p.name not in ('manifest.json','README.md')]}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
