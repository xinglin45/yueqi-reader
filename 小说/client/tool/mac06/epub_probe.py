#!/usr/bin/env python3
"""Bounded, strict EPUB3 research loader; not a general production importer."""
from __future__ import annotations
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / 'fixtures/novel/mac06'
ASSETS = ROOT / '小说/client/assets/mac06'
NS = {'c':'urn:oasis:names:tc:opendocument:xmlns:container', 'o':'http://www.idpf.org/2007/opf', 'h':'http://www.w3.org/1999/xhtml'}
XHTML = '{http://www.w3.org/1999/xhtml}'
EPUB = '{http://www.idpf.org/2007/ops}'
CSP = "default-src 'none'; img-src reader-probe:; style-src 'unsafe-inline' reader-probe:; font-src reader-probe:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

class Rejected(ValueError): pass

def local_path(base: str, href: str) -> str:
    u = urlsplit(href)
    if u.scheme or u.netloc or u.query: raise Rejected('external_or_query')
    decoded = unquote(u.path)
    if '%' in decoded or '\\' in decoded or '\x00' in decoded or decoded.startswith('/'): raise Rejected('unsafe_path')
    parts = list(PurePosixPath(base).parent.parts)
    for part in decoded.split('/'):
        if part in ('', '.'): continue
        if part == '..':
            if not parts: raise Rejected('path_escape')
            parts.pop()
        else: parts.append(part)
    return '/'.join(parts)

def xml(data: bytes) -> ET.Element:
    if re.search(br'<!\s*(DOCTYPE|ENTITY)', data, re.I): raise Rejected('xml_dtd')
    try: return ET.fromstring(data)
    except ET.ParseError: raise Rejected('invalid_xml') from None

def text_of(node: ET.Element) -> str:
    if node.tag in (XHTML+'rt', XHTML+'rp', XHTML+'script', XHTML+'style') or node.get('aria-hidden') == 'true': return ''
    return (node.text or '') + ''.join(text_of(child) + (child.tail or '') for child in node)

def utf16len(text: str) -> int: return len(text.encode('utf-16-le')) // 2

def load(data: bytes) -> dict:
    if len(data) > 4_000_000: raise Rejected('archive_size')
    try: archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile: raise Rejected('invalid_zip') from None
    entries = archive.infolist(); names = [e.filename for e in entries]
    if len(entries) > 256 or len(set(names)) != len(names): raise Rejected('entry_count_or_duplicate')
    if sum(e.file_size for e in entries) > 8_000_000: raise Rejected('expanded_size')
    if not entries or entries[0].filename != 'mimetype' or entries[0].compress_type != zipfile.ZIP_STORED: raise Rejected('mimetype_order')
    for entry in entries:
        if entry.is_dir(): continue
        if str(PurePosixPath(entry.filename)) != entry.filename or '..' in PurePosixPath(entry.filename).parts or entry.filename.startswith('/') or '\\' in entry.filename or '%' in entry.filename: raise Rejected('zip_path')
        if stat.S_ISLNK(entry.external_attr >> 16): raise Rejected('zip_symlink')
        if entry.file_size > 4_000_000 or entry.file_size / max(1, entry.compress_size) > 100: raise Rejected('zip_budget')
        if entry.flag_bits & 1: raise Rejected('encrypted_zip')
    files = {name: archive.read(name) for name in names if not name.endswith('/')}
    if files.get('mimetype') != b'application/epub+zip': raise Rejected('mimetype')
    if 'META-INF/encryption.xml' in files: raise Rejected('encryption_unsupported')
    root = xml(files.get('META-INF/container.xml', b''))
    package_ref = root.find('c:rootfiles/c:rootfile', NS)
    if package_ref is None: raise Rejected('container')
    package_path = local_path('root', package_ref.get('full-path',''))
    package = xml(files.get(package_path,b''))
    manifest = {}
    for item in package.findall('o:manifest/o:item',NS):
        key = item.get('id','')
        if not key or key in manifest: raise Rejected('manifest_id')
        path = local_path(package_path,item.get('href',''))
        if path not in files: raise Rejected('missing_resource')
        manifest[key] = {'path':path,'mime':item.get('media-type',''),'properties':item.get('properties','')}
    allowed_types = {'application/xhtml+xml','text/css','image/png','font/ttf','text/plain'}
    if any(item['mime'] not in allowed_types for item in manifest.values()): raise Rejected('media_type_unsupported')
    resources = {}; documents = []; stripped = []
    for key,item in manifest.items():
        path = item['path']; payload = files[path]
        if item['mime'] == 'application/xhtml+xml':
            tree = xml(payload)
            seen = set()
            for node in tree.iter():
                id_ = node.get('id')
                if id_ and id_ in seen: raise Rejected('duplicate_dom_id')
                if id_: seen.add(id_)
            for parent in list(tree.iter()):
                for child in list(parent):
                    if child.tag == XHTML+'script':
                        parent.remove(child); stripped.append('element')
                    elif child.tag not in {XHTML+t for t in ['html','head','title','meta','link','body','h1','h2','p','strong','em','a','img','figure','figcaption','blockquote','ruby','rt','rp','nav','ol','li','span','div','section','article','main','header','footer','aside','ul','br','hr','code','pre','sub','sup']}:
                        raise Rejected('html_element_unsupported')
                for attr in list(parent.attrib):
                    if attr.lower().startswith('on') or attr.lower() in ('srcdoc','style'):
                        del parent.attrib[attr]; stripped.append('attribute')
                for attr in ('src','href'):
                    href = parent.get(attr)
                    if href is None: continue
                    try: target = local_path(path,href)
                    except Rejected:
                        del parent.attrib[attr]; stripped.append('external_reference'); continue
                    if target not in {x['path'] for x in manifest.values()}:
                        del parent.attrib[attr]; stripped.append('unlisted_reference')
            head=tree.find('h:head',NS)
            if head is None: raise Rejected('head_missing')
            # A book cannot override the host content security policy.
            for child in list(head):
                if child.tag == XHTML+'meta' and child.get('http-equiv'): head.remove(child)
            head.insert(0,ET.Element(XHTML+'meta', {'http-equiv':'Content-Security-Policy','content':CSP}))
            blocks=[]
            body=tree.find('h:body',NS)
            if body is None: raise Rejected('body_missing')
            for node in body.iter():
                if node.tag not in {XHTML+t for t in ('h1','h2','p','blockquote')}: continue
                if not node.get('id'):
                    candidate=f'probe-block-{len(blocks)}'
                    while candidate in seen: candidate+='-x'
                    node.set('id',candidate);seen.add(candidate)
                text=text_of(node)
                blocks.append({'id':node.get('id'),'tag':node.tag.removeprefix(XHTML),'text':text,'utf16_length':utf16len(text)})
            payload=ET.tostring(tree,encoding='utf-8',xml_declaration=True)
            documents.append({'id':key,'path':path,'blocks':blocks})
        elif item['mime'] == 'text/css':
            css=payload.decode('utf-8')
            # Probe profile: internal, declared CSS URLs only; imports unsupported.
            if re.search(r'@import|expression\s*\(',css,re.I): raise Rejected('css_active_or_import')
            for url in re.findall(r'url\(\s*[\'"]?([^\)\'\"]+)',css):
                if local_path(path,url) not in {x['path'] for x in manifest.values()}: raise Rejected('css_resource')
        resources[path]={'mime':item['mime'],'base64':base64.b64encode(payload).decode()}
    spine=[]
    for ref in package.findall('o:spine/o:itemref',NS):
        idref=ref.get('idref')
        doc=next((d for d in documents if d['id']==idref),None)
        if doc is None: raise Rejected('spine_reference')
        spine.append(doc)
    nav=next((item for item in manifest.values() if 'nav' in item['properties'].split()),None)
    if nav is None: raise Rejected('nav_missing')
    nav_tree=xml(base64.b64decode(resources[nav['path']]['base64']))
    toc=[{'title':text_of(a),'href':local_path(nav['path'],a.get('href','')),'fragment':urlsplit(a.get('href','')).fragment} for a in nav_tree.findall('.//h:a',NS)]
    return {'schema':1,'revision':hashlib.sha256(data).hexdigest(),'spine':spine,'toc':toc,'resources':resources,'stripped':stripped,'offset_unit':'utf16_code_unit'}

def png() -> bytes:
    import struct,zlib
    def chunk(kind,payload): return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload))
    w,h=96,56
    raw=b''.join(b'\0'+b''.join(bytes((161,183,158)) if y > 40-abs(x-48)//3 else bytes((240,233,215)) for x in range(w)) for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')

def fixture() -> bytes:
    h='http://www.w3.org/1999/xhtml'
    def doc(title,body): return f'<?xml version="1.0" encoding="utf-8"?><html xmlns="{h}" xmlns:epub="http://www.idpf.org/2007/ops" lang="zh"><head><title>{title}</title><link rel="stylesheet" href="../styles/book.css"/></head><body>{body}</body></html>'.encode()
    first='<h1 id="title1">第一章　雨后山路</h1><p id="p1">清晨，<strong>山间来信</strong>放在窗边。山間來信仍保留繁體原文。</p><p id="p2">标点：100%_完成；📖 e&#x301; 后面是<em>雨后山路</em>。</p><figure><img src="../images/hill.png" alt="自产山形色块"/><figcaption>图一 · 自产几何样本</figcaption></figure><blockquote id="quote">慢一点，读完这一段。</blockquote><p id="ruby">沿着<ruby>山<rt>shān</rt></ruby>路，林舟向前走。</p><p id="font"><span class="ornament" aria-hidden="true">&#xe068;</span> 内嵌字体试验；装饰不进入朗读。</p><p id="link"><a href="ch2.xhtml#target">去第二章的目标段落</a></p><script>window.untrustedBookExecuted=true;</script>'
    second='<h1 id="title2">第二章　山間來信</h1><p id="target">📖 e&#x301;，目标位置在这里；这是用于选字、高亮、搜索与听书映射的同一段文字。</p>'+''.join(f'<p id="long{i}">第{i}段。'+('窗外的山路渐渐明亮，朋友在路的尽头等待。'*4)+'</p>' for i in range(16))
    files={
      'META-INF/container.xml':b'<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
      'OEBPS/package.opf':''' <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">local.yueqi.mac06.1</dc:identifier><dc:title>山路与来信</dc:title><dc:language>zh</dc:language><dc:creator>阅读软件自产技术样本</dc:creator><meta property="dcterms:modified">2026-10-19T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/><item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/><item id="css" href="styles/book.css" media-type="text/css"/><item id="image" href="images/hill.png" media-type="image/png"/><item id="font" href="fonts/Phosphor-Light.ttf" media-type="font/ttf"/><item id="license" href="LICENSE-phosphor.txt" media-type="text/plain"/></manifest><spine><itemref idref="ch1"/><itemref idref="ch2"/></spine></package>'''.strip().encode(),
      'OEBPS/nav.xhtml':f'<html xmlns="{h}" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="text/ch1.xhtml#title1">第一章 雨后山路</a></li><li><a href="text/ch2.xhtml#target">第二章 山間來信</a></li></ol></nav></body></html>'.encode(),
      'OEBPS/text/ch1.xhtml':doc('第一章',first), 'OEBPS/text/ch2.xhtml':doc('第二章',second),
      'OEBPS/styles/book.css':b'''@font-face{font-family:ProbeIcon;src:url('../fonts/Phosphor-Light.ttf')}html{background:#fbf9f5;color:#2d2925}body{font-family:'Songti SC',serif;font-size:23px;line-height:1.9;margin:0;padding:32px;max-width:760px}h1{font-size:32px;border-bottom:1px solid #dedad3;padding-bottom:18px}strong{color:#9f654b;font-weight:700}em{font-style:italic}img{width:192px;image-rendering:pixelated}blockquote{border-left:3px solid #9f654b;padding-left:18px;margin-left:0}figure{margin-left:0}figcaption{font-size:13px;color:#6d6760}.ornament{font-family:ProbeIcon}''',
      'OEBPS/images/hill.png':png(),
    }
    font_path=Path.home()/'.pub-cache/hosted/pub.dev/phosphor_icons-3.0.1/lib/fonts/Phosphor-Light.ttf'
    files['OEBPS/fonts/Phosphor-Light.ttf']=font_path.read_bytes()
    files['OEBPS/LICENSE-phosphor.txt']=(ROOT/'docs/licenses/mac-02/phosphor_icons-LICENSE.txt').read_bytes()
    output=io.BytesIO()
    with zipfile.ZipFile(output,'w') as archive:
        for name,payload in [('mimetype',b'application/epub+zip'),*sorted(files.items())]:
            entry=zipfile.ZipInfo(name,date_time=(2026,10,19,0,0,0)); entry.compress_type=zipfile.ZIP_STORED if name=='mimetype' else zipfile.ZIP_DEFLATED
            archive.writestr(entry,payload)
    return output.getvalue()

def generate():
    FIXTURE.mkdir(parents=True,exist_ok=True);ASSETS.mkdir(parents=True,exist_ok=True)
    data=fixture(); (FIXTURE/'mountain-letter.epub').write_bytes(data); (ASSETS/'mountain-letter.epub').write_bytes(data)
    value=load(data)
    serialized=json.dumps(value,ensure_ascii=False,indent=2)+'\n'
    (ASSETS/'fixture.json').write_text(serialized)
    summary={k:v for k,v in value.items() if k!='resources'}
    summary['resource_count']=len(value['resources']);summary['epub_bytes']=len(data)
    summary['font_sha256']=hashlib.sha256(base64.b64decode(value['resources']['OEBPS/fonts/Phosphor-Light.ttf']['base64'])).hexdigest()
    (FIXTURE/'manifest.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(f'Generated bounded EPUB: {len(data)} bytes, {len(value["spine"])} spine, {len(value["toc"])} TOC')
if __name__=='__main__': generate()
