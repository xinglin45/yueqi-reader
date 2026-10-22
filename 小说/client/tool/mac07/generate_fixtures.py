"""Deterministic, project-owned neutral EPUB reader and rejection fixtures."""
from pathlib import Path
import hashlib
import importlib.util
import json
import zipfile
import io
from PIL import Image, __version__ as pillow_version

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'fixtures/novel/mac07'
OUT.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('owned_mac06', ROOT / '小说/client/tool/mac06/epub_probe.py')
owned = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owned)
NS = 'http://www.w3.org/1999/xhtml'

def xhtml(title, body):
    return f'<html xmlns="{NS}" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>{title}</title><link rel="stylesheet" href="../style.css"/></head><body>{body}</body></html>'.encode()

container = b'<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="Book/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
opf = '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>山路与微光</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="text/two.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="css" href="style.css" media-type="text/css"/><item id="png" href="images/hill.png" media-type="image/png"/><item id="jpg" href="images/hill.jpg" media-type="image/jpeg"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>'''
image = Image.new('RGB', (96, 56))
image.putdata([(161,183,158) if y > 40-abs(x-48)//3 else (240,233,215) for y in range(56) for x in range(96)])
jpeg = io.BytesIO()
image.save(jpeg, 'JPEG', quality=82, subsampling=0, optimize=False)

base = {
    'mimetype': b'application/epub+zip',
    'META-INF/container.xml': container,
    'Book/package.opf': opf.encode(),
    'Book/text/one.xhtml': xhtml('第一章 雨后', '<h1 id="opening">第一章　雨后山路</h1><p id="quote">清晨，<strong>山间微光</strong>落在窗边。📖 e&#x301; 繁體原文。</p><p>沿著<ruby>山<rt>shān</rt></ruby>路向前。</p><table><tbody><tr><th>时刻</th><td>清晨</td></tr></tbody></table><img src="../images/hill.png" alt="自产山形色块"/><img src="../images/hill.jpg" alt="自产JPEG色块"/><p><a href="two.xhtml#target">去第二章目标段落</a></p><script>window.untrustedBookExecuted=true;</script><p onclick="window.untrustedBookExecuted=true">正文不能取得主机桥接。</p><img src="https://example.invalid/remote.png" alt="外联已禁用"/>'),
    'Book/text/two.xhtml': xhtml('第二章 微光', '<h1 id="second">第二章　微光</h1><p id="target">📖 e&#x301;，目标位置在这里；這是同一份原文映射。</p><p>山风停下之后，他合上书。</p>'),
    'Book/nav.xhtml': f'<html xmlns="{NS}" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="text/one.xhtml#opening">第一章 雨后山路</a><ol><li><a href="text/one.xhtml#quote">窗边微光</a></li></ol></li><li><a href="text/two.xhtml#target">第二章 微光</a></li></ol></nav></body></html>'.encode(),
    'Book/style.css': b'body{font-size:23px;line-height:1.9}strong{color:#9f654b}table{border-collapse:collapse}td,th{border:1px solid #9f654b;padding:6px}img{width:192px}h1{border-bottom:1px solid #dedad3}',
    'Book/images/hill.png': owned.png(),
    'Book/images/hill.jpg': jpeg.getvalue(),
}

def write(name, files, symlink=False):
    with zipfile.ZipFile(OUT/name, 'w') as archive:
        for path, data in files.items():
            info = zipfile.ZipInfo(path, (2026,10,22,0,0,0))
            info.compress_type = zipfile.ZIP_STORED if path == 'mimetype' else zipfile.ZIP_DEFLATED
            if symlink and path.endswith('hill.png'):
                info.create_system = 3
                info.external_attr = 0o120777 << 16
            archive.writestr(info, data)

write('流式EPUB3.epub', base)
v2 = base.copy()
v2['Book/package.opf'] = opf.replace('version="3.0"','version="2.0"').replace('properties="nav"','').replace('<spine>','<spine toc="ncx">').replace('</manifest>','<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>').encode()
v2['Book/toc.ncx'] = b'<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint id="n1"><navLabel><text>First</text></navLabel><content src="text/one.xhtml#opening"/></navPoint><navPoint id="n2"><navLabel><text>Second</text></navLabel><content src="text/two.xhtml#target"/></navPoint></navMap></ncx>'
write('流式EPUB2.epub', v2)
write('缺失图片.epub', {k:v for k,v in base.items() if not k.endswith('hill.png')})
write('片段缺失.epub', base | {'Book/text/two.xhtml': base['Book/text/two.xhtml'].replace(b'id="target"',b'id="other"')})
write('固定版式.epub', base | {'Book/package.opf': opf.replace('</metadata>','<meta property="rendition:layout">pre-paginated</meta></metadata>').encode()})
write('不支持SVG.epub', base | {'Book/package.opf': opf.replace('image/png','image/svg+xml').encode()})
write('CSS导入.epub', base | {'Book/style.css': b'@import "https://example.invalid/remote.css";'})
write('CSS转义.epub', base | {'Book/style.css': br'body{background:url(\68ttps://example.invalid/x)}'})
write('DTD实体.epub', base | {'Book/text/two.xhtml': b'<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><html>&e;</html>'})
write('重复DOM标识.epub', base | {'Book/text/two.xhtml': xhtml('duplicate','<p id="same">甲</p><p id="same">乙</p>')})
write('符号链接.epub', base, symlink=True)
write('双重编码路径.epub', base | {'Book/text/two.xhtml': xhtml('bad','<img src="%252e%252e/%252e%252e/private"/>')})
write('超大图片尺寸.epub', base | {'Book/images/hill.png': base['Book/images/hill.png'][:16]+(100000).to_bytes(4,'big')+base['Book/images/hill.png'][20:]})
write('加密.epub', base | {'META-INF/encryption.xml': b'<encryption/>'})
write('规范文本.epub', base | {'Book/text/two.xhtml': xhtml('规范文本', '<h1 id="second">第二章</h1><p id="target">正文甲\r\n正文乙\r<![CDATA[長段📖e\u0301'+'長段📖e\u0301'*1000+']]></p>')})
manifest = {'date':'2026-10-22','provenance':'Project-owned neutral Chinese text, generated geometric PNG/JPEG and package mutations; no third-party book or adult body.',
    'jpeg_generator':f'Pillow {pillow_version}; project-owned procedural pixels',
    'files':[{'name':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUT.glob('*.epub'))]}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(f'Generated {len(manifest["files"])} owned EPUB fixtures.')
