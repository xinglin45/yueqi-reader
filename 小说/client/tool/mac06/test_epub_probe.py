import io, unittest, zipfile
from pathlib import Path
from epub_probe import FIXTURE, Rejected, load, local_path, utf16len

class EpubProbeTest(unittest.TestCase):
    def setUp(self): self.data=(FIXTURE/'mountain-letter.epub').read_bytes()
    def mutate(self, update=None, extra=None):
        output=io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(self.data)) as source, zipfile.ZipFile(output,'w') as target:
            for entry in source.infolist():
                data=source.read(entry.filename)
                if update: data=update(entry.filename,data)
                target.writestr(entry,data)
            if extra: target.writestr(*extra)
        return output.getvalue()
    def test_same_fixture_canonical_text_and_offsets(self):
        value=load(self.data)
        self.assertEqual(len(value['spine']),2);self.assertEqual(len(value['toc']),2)
        block=next(b for b in value['spine'][0]['blocks'] if b['id']=='ruby')
        self.assertEqual(block['text'],'沿着山路，林舟向前走。')
        self.assertEqual(utf16len('📖 e\u0301'),5)
        self.assertIn('element',value['stripped'])
        self.assertNotIn(b'<script',__import__('base64').b64decode(value['resources']['OEBPS/text/ch1.xhtml']['base64']))
    def test_root_and_encoded_path_escape(self):
        for path in ['../../../secret','%2e%2e/%2e%2e/%2e%2e/secret','%252e%252e/x','file:///etc/passwd','https://example.invalid/x','//other/x','/private','..\\secret']:
            with self.subTest(path=path),self.assertRaises(Rejected):local_path('OEBPS/text/ch.xhtml',path)
        self.assertEqual(local_path('OEBPS/text/ch.xhtml','../images/hill.png'),'OEBPS/images/hill.png')
    def test_zip_escape(self):
        with self.assertRaises(Rejected):load(self.mutate(extra=('../outside',b'x')))
    def test_symlink(self):
        link=zipfile.ZipInfo('OEBPS/link');link.external_attr=(0o120777<<16)
        with self.assertRaises(Rejected):load(self.mutate(extra=(link,b'/etc/passwd')))
    def test_duplicate_entry(self):
        with self.assertWarns(UserWarning):data=self.mutate(extra=('OEBPS/text/ch1.xhtml',b'bad'))
        with self.assertRaises(Rejected):load(data)
    def test_dtd(self):
        with self.assertRaises(Rejected):load(self.mutate(lambda name,data:b'<!DOCTYPE html [<!ENTITY x SYSTEM "file:///etc/passwd">]>'+data if name.endswith('ch1.xhtml') else data))
    def test_missing_resource_and_bad_xml(self):
        for payload in [b'<bad',b'<html/>']:
            with self.assertRaises(Rejected):load(self.mutate(lambda name,data:payload if name.endswith('package.opf') else data))
    def test_encryption_metadata_rejected(self):
        with self.assertRaises(Rejected):load(self.mutate(extra=('META-INF/encryption.xml',b'<encryption/>')))
    def test_duplicate_dom_id(self):
        with self.assertRaises(Rejected):load(self.mutate(lambda name,data:data.replace(b'id="p2"',b'id="p1"') if name.endswith('ch1.xhtml') else data))
    def test_unknown_content_is_rejected_not_silently_dropped(self):
        with self.assertRaises(Rejected):load(self.mutate(lambda name,data:data.replace(b'<p id="p1">',b'<canvas/><p id="p1">') if name.endswith('ch1.xhtml') else data))
    def test_external_css_rejected(self):
        with self.assertRaises(Rejected):load(self.mutate(lambda name,data:data+b'@import "https://example.invalid/x";' if name.endswith('.css') else data))
    def test_expansion_budget(self):
        with self.assertRaises(Rejected):load(self.mutate(extra=('OEBPS/bomb',b'0'*4_000_001)))
    def test_corrupt_zip(self):
        with self.assertRaises(Rejected):load(b'not a zip')
if __name__=='__main__':unittest.main()
