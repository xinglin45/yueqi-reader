import Cocoa
import FlutterMacOS
import WebKit

final class EpubFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        EpubWebView(viewId: viewId, messenger: messenger, args: args as? [String: Any] ?? [:])
    }
}

/// Only opaque, current-session resource IDs reach Dart. Never opens a URL or a
/// filesystem path. Tasks are bounded, cancelled and retired exactly once.
final class EpubScheme: NSObject, WKURLSchemeHandler {
    let host: String
    var fetch: ((String, @escaping (Any?) -> Void) -> Void)?
    private var tasks = [ObjectIdentifier: WKURLSchemeTask]()
    private var queue = [ObjectIdentifier]()
    private var running = Set<ObjectIdentifier>()
    var rejected = 0
    var served = Set<String>()
    init(_ host: String) { self.host = host }
    func resource(_ url: URL?) -> String? {
        guard let u = url, let parts = URLComponents(url: u, resolvingAgainstBaseURL: false),
              u.scheme == "reader-book", u.host == host, parts.user == nil, parts.password == nil,
              parts.port == nil, parts.query == nil, parts.percentEncodedPath.range(of: "^/r[0-9]{1,4}$", options: .regularExpression) != nil else { return nil }
        return String(u.path.dropFirst())
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard task.request.httpMethod == "GET", resource(task.request.url) != nil, tasks.count < 128, fetch != nil else {
            rejected += 1; task.didFailWithError(NSError(domain: "ReaderResource", code: 403)); return
        }
        let key = ObjectIdentifier(task)
        tasks[key] = task; queue.append(key); drain()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        tasks.removeValue(forKey: key)
        queue.removeAll { $0 == key }
        // In-flight callbacks still occupy a slot until their response/timeout.
    }
    private func drain() {
        while running.count < 8 && !queue.isEmpty {
            let key = queue.removeFirst()
            guard let task = tasks[key], let rid = resource(task.request.url) else { continue }
            running.insert(key)
            var completed = false
            let finish: (Any?) -> Void = { [weak self] value in
                guard !completed, let self = self else { return }; completed = true
                self.running.remove(key)
                guard let current = self.tasks.removeValue(forKey: key) else { self.drain(); return }
                guard let item = value as? [String: Any], let typed = item["bytes"] as? FlutterStandardTypedData,
                      let mime = item["mime"] as? String, typed.data.count <= 16 * 1024 * 1024,
                      let url = current.request.url else {
                    self.rejected += 1; current.didFailWithError(NSError(domain: "ReaderResource", code: 403)); self.drain(); return
                }
                self.served.insert(rid)
                current.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: typed.data.count,
                    textEncodingName: mime == "application/xhtml+xml" || mime == "text/css" ? "utf-8" : nil))
                current.didReceive(typed.data); current.didFinish(); self.drain()
            }
            fetch?(rid, finish)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish(nil) }
        }
    }
    func close() {
        fetch = nil
        let old = tasks; tasks.removeAll(); queue.removeAll(); running.removeAll()
        for task in old.values { task.didFailWithError(NSError(domain: "ReaderResource", code: 410)) }
    }
}

final class EpubWebView: NSView, WKNavigationDelegate, WKUIDelegate {
    private let channel: FlutterMethodChannel
    private let scheme: EpubScheme
    private let web: WKWebView
    private let resource: String
    private let spines: Set<String>
    private let initial: [String: Any]
    private var alive = true
    private var ready = false
    private var started = false
    private var rulesReady = false
    private var blocked = 0
    private var navigation: WKNavigation?
    private var replies = [UUID: FlutterResult]()
    init(viewId: Int64, messenger: FlutterBinaryMessenger, args: [String: Any]) {
        let session = args["session"] as? String ?? "invalid"
        scheme = EpubScheme(session)
        resource = args["resource"] as? String ?? "invalid"
        spines = Set(args["spines"] as? [String] ?? [])
        initial = args
        channel = FlutterMethodChannel(name: "reader/epub/\(viewId)", binaryMessenger: messenger)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(scheme, forURLScheme: "reader-book")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Book JavaScript is also removed and forbidden by the host CSP.
        // Trusted operations execute only in the isolated defaultClient world.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        web = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        web.navigationDelegate = self; web.uiDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false; addSubview(web)
        NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo: topAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor),
            web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor)])
        scheme.fetch = { [weak self] rid, result in
            guard let self = self, self.alive else { result(nil); return }
            self.channel.invokeMethod("resource", arguments: ["session": session, "id": rid], result: result)
        }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self, self.alive else { result(FlutterError(code: "disposed", message: nil, details: nil)); return }
            if call.method == "start" { self.started = true; self.begin(); result(nil); return }
            if call.method == "dispose" { self.close(); result(nil); return }
            guard self.ready else { result(FlutterError(code: "not_ready", message: nil, details: nil)); return }
            let params = call.arguments as? [String: Any] ?? [:]
            if call.method == "capture" {
                self.run("return globalThis.readerHost.capture();", args: [:], result: result)
            } else if call.method == "layout", let size = params["size"] as? Double, size.isFinite, size >= 16, size <= 36, let dark = params["dark"] as? Bool {
                self.run("return await globalThis.readerHost.layout(size,dark);", args: ["size": size, "dark": dark], result: result)
            } else if call.method == "restore", let anchor = params["anchor"] as? [String: Any] {
                self.run("return globalThis.readerHost.restore(anchor);", args: ["anchor": anchor], result: result)
            } else if call.method == "viewport" {
                self.run("return globalThis.readerHost.viewport();", args: [:], result: result)
            } else if call.method == "configure", let prefs = params["preferences"] as? [String: Any], let dark = params["dark"] as? Bool {
                self.run("return await globalThis.readerHost.configure(prefs,dark);", args: ["prefs": prefs, "dark": dark], result: result)
            } else if call.method == "page", let delta = params["delta"] as? Int, abs(delta) == 1 {
                self.run("return globalThis.readerHost.turn(delta);", args: ["delta": delta], result: result)
            } else if call.method == "checks" {
                self.run(Self.checks, args: [:]) { [weak self] value in
                    guard let self = self, self.alive else { result(FlutterError(code: "disposed", message: nil, details: nil)); return }
                    guard !(value is FlutterError) else { result(value); return }
                    // Read the actual page world separately; isolated globals are not evidence.
                    self.web.callAsyncJavaScript("return globalThis.untrustedBookExecuted === true || typeof globalThis.readerHost !== 'undefined';", arguments: [:], in: nil, in: .page) { page in
                        var pageFlag: Any = NSNull()
                        if case .success(let flag) = page { pageFlag = flag }
                        result(["dom": value ?? NSNull(), "page_script_or_host_visible": pageFlag, "denied": self.scheme.rejected,
                            "blocked_navigation": self.blocked, "served": self.scheme.served.sorted()])
                    }
                }
            } else { result(FlutterError(code: "unsupported", message: nil, details: nil)) }
        }
        let rules = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^reader-book://\(session)/r[0-9]+(#.*)?$"},"action":{"type":"ignore-previous-rules"}}]
        """
        guard session.range(of: "^s[a-f0-9]{32}$", options: .regularExpression) != nil,
              spines.contains(resource), spines.count <= 512, spines.allSatisfy({ $0.range(of: "^r[0-9]{1,4}$", options: .regularExpression) != nil }) else {
            notifyError("invalid_session"); return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "local.yueqi.epub.offline", encodedContentRuleList: rules) { [weak self] list, error in
            guard let self = self, self.alive else { return }
            guard let list = list, error == nil else { self.notifyError("resource_policy"); return }
            self.web.configuration.userContentController.add(list)
            self.rulesReady = true; self.begin()
        }
    }
    private func begin() {
        guard alive, started, rulesReady, navigation == nil else { return }
        var url = URLComponents(); url.scheme = "reader-book"; url.host = scheme.host; url.path = "/\(resource)"
        if let fragment = initial["fragment"] as? String, !fragment.isEmpty { url.fragment = fragment }
        guard let target = url.url else { notifyError("invalid_session"); return }
        navigation = web.load(URLRequest(url: target))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private func notifyError(_ kind: String, code: Int = 0) { if alive { NSLog("EPUB_NATIVE %@", kind); channel.invokeMethod("error", arguments: ["kind": kind, "code": code]) } }
    private func close() {
        guard alive else { return }; alive = false; ready = false
        web.isHidden = true; web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil
        scheme.close(); channel.setMethodCallHandler(nil)
        let pending = replies; replies.removeAll()
        for reply in pending.values { reply(FlutterError(code: "disposed", message: nil, details: nil)) }
    }
    deinit { close() }
    private func run(_ script: String, args: [String: Any], result: @escaping FlutterResult) {
        let id = UUID(); replies[id] = result
        let finish: FlutterResult = { [weak self] value in
            guard let self = self, let reply = self.replies.removeValue(forKey: id) else { return }; reply(value)
        }
        web.callAsyncJavaScript(script, arguments: args, in: nil, in: .defaultClient) { value in
            switch value { case .success(let data): finish(data); case .failure: finish(FlutterError(code: "renderer_operation", message: nil, details: nil)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(FlutterError(code: "renderer_timeout", message: nil, details: nil)) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard alive, navigation === self.navigation else { return }
        run(Self.bootstrap, args: ["session": scheme.host, "resource": resource,
            "size": initial["size"] as? Double ?? 24.0, "dark": initial["dark"] as? Bool ?? false,
            "anchor": initial["anchor"] ?? NSNull()]) { [weak self] value in
            guard let self = self, self.alive else { return }
            if value is FlutterError {
                self.web.callAsyncJavaScript("return globalThis.readerPhase || 0;", arguments: [:], in: nil, in: .defaultClient) { outcome in
                    var phase = 0
                    if case .success(let result) = outcome { phase = (result as? NSNumber)?.intValue ?? 0 }
                    self.notifyError("text_mapping", code: (0...8).contains(phase) ? phase : 0)
                }
                return
            }
            self.ready = true; self.channel.invokeMethod("ready", arguments: value)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === self.navigation { notifyError("load_failed", code: (error as NSError).code) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === self.navigation { notifyError("load_failed", code: (error as NSError).code) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; web.isHidden = true; notifyError("process_terminated") }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard alive, action.targetFrame?.isMainFrame == true, let rid = scheme.resource(action.request.url), spines.contains(rid) else {
            blocked += 1; decisionHandler(.cancel); return
        }
        if action.navigationType == .linkActivated {
            channel.invokeMethod("navigate", arguments: ["session": scheme.host, "resource": rid, "fragment": action.request.url?.fragment ?? ""])
            decisionHandler(.cancel); return
        }
        guard rid == resource else { blocked += 1; decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { blocked += 1; return nil }

    // Host-owned code: no EPUB scripts, dynamic source strings or page-world
    // message handler. Offsets are UTF-16 and checked again against Dart text.
    static let bootstrap = #"""
    globalThis.readerPhase=1;
    const spans=[...document.body.querySelectorAll('[data-rk]')];
    const blocks=Object.fromEntries(spans.map(e=>[e.getAttribute('data-rk'),e.textContent]));
    const nodes=spans.map(e=>[e,e.firstChild]);
    let last=null;
    const capture=()=>{
      const s=getSelection();const segments=[];
      if(s&&s.rangeCount&&!s.isCollapsed){
        const r=s.getRangeAt(0);
        for(const [el,n] of nodes){
          if(!n||n.nodeType!==3)continue;
          const a=r.comparePoint(n,0),z=r.comparePoint(n,n.length);
          if(z<0||a>0)continue;
          const start=r.startContainer===n?r.startOffset:(a<0?n.length:0);
          const end=r.endContainer===n?r.endOffset:(z>0?0:n.length);
          if(end>start)segments.push({block:el.getAttribute('data-rk'),start,end,exact:n.data.slice(start,end)});
        }
        if(segments.length>32||segments.some(x=>x.end-x.start>512)||segments.reduce((n,x)=>n+x.end-x.start,0)>2048)throw Error('selection_limit');
        if(segments.length)last={session,resource,kind:'selection',segments};
      }
      if(last)return last;
      return viewport();
    };
    document.addEventListener('selectionchange',()=>{try{const s=getSelection();if(s&&!s.isCollapsed)capture();}catch{last=null;}});
    let mode='scroll',prefs=null,systemDark=false,layoutTicket=0,reflow=false,cursor=null,retained=null,suppressScrollUntil=0,waitingForFonts=false;
    const visible=()=>{
      for(const [el,n] of nodes){
        if(!n||n.nodeType!==3||!n.length)continue;
        const rects=[...el.getClientRects()];
        if(!rects.some(r=>r.bottom>1&&r.top<innerHeight&&r.right>0&&r.left<innerWidth))continue;
        for(let at=0;at<n.length;){
          const next=at+(n.data.codePointAt(at)>65535?2:1),r=document.createRange();r.setStart(n,at);r.setEnd(n,next);
          if([...r.getClientRects()].some(b=>b.bottom>1&&b.top<innerHeight&&b.left>=0&&b.left<innerWidth)){
            return {session,resource,segments:[{block:el.getAttribute('data-rk'),start:at,end:at,exact:''}]};
          }at=next;
        }
      }return cursor||{session,resource,segments:[{block:spans[0].getAttribute('data-rk'),start:0,end:0,exact:''}]};
    };
    const viewport=()=>{if(!cursor)cursor=visible();return cursor;};
    const restore=a=>{
      if(!a)return false;
      const el=spans.find(e=>e.getAttribute('data-rk')===a.block_id),n=el?.firstChild;
      if(!n||n.nodeType!==3||!Number.isInteger(a.start)||!Number.isInteger(a.end)||a.start<0||a.end<a.start||a.end>n.length||n.data.slice(a.start,a.end)!==a.exact)throw Error('anchor');
      const r=document.createRange();r.setStart(n,a.start);r.setEnd(n,Math.min(n.length,Math.max(a.end,a.start+(n.data.codePointAt(a.start)>65535?2:1))));
      const rect=r.getClientRects()[0]||el.getBoundingClientRect();
      suppressScrollUntil=performance.now()+250;
      if(mode==='scroll')scrollTo(0,Math.max(0,scrollY+rect.top-4));
      else scrollTo(Math.floor(Math.max(0,scrollX+rect.left)/innerWidth)*innerWidth,0);
      if(a.end>a.start){r.setEnd(n,a.end);const s=getSelection();s.removeAllRanges();s.addRange(r);}
      cursor={session,resource,segments:[{block:a.block_id,start:a.start,end:a.start,exact:''}]};return true;
    };
    const style=document.createElementNS('http://www.w3.org/1999/xhtml','style');document.head.append(style);
    const configure=async(p,dark)=>{
      for(const [key,min,max] of [['size',16,36],['line_height',1.2,2.4],['paragraph_spacing',0,40],['margin',8,64],['width',360,1400]])
        if(!Number.isFinite(p[key])||p[key]<min||p[key]>max)throw Error('layout_limit');
      if(!['scroll','paged','columns'].includes(p.layout)||!['song','sans','mono'].includes(p.font)||!['app','system','paper','dark','green'].includes(p.theme))throw Error('layout_enum');
      globalThis.readerPhase=3;
      const before=cursor||visible(),ticket=++layoutTicket;reflow=true;prefs=p;systemDark=dark;mode=p.layout;
      const dim=p.theme==='dark'||(['app','system'].includes(p.theme)&&dark),green=p.theme==='green',bg=green?'#dae5d4':dim?'#252421':'#fbf9f5',fg=green?'#263329':dim?'#e9e5dc':'#2d2925';
      const columns=mode==='columns'&&innerWidth>=720?2:1,font={song:"'Songti SC',serif",sans:"'PingFang SC',sans-serif",mono:"Menlo,monospace"}[p.font];
      style.textContent=`html{background:${bg}!important;color:${fg}!important;scroll-behavior:auto!important;overflow:${mode==='scroll'?'auto':'auto hidden'}!important}body{background:${bg}!important;color:${fg}!important;font-size:${p.size}px!important;line-height:${p.line_height}!important;font-family:${font}!important;margin:0 auto!important;padding:${p.margin}px!important;box-sizing:border-box!important;width:100%!important;max-width:${mode==='scroll'?p.width+'px':'none'}!important;height:${mode==='scroll'?'auto':innerHeight+'px'}!important;column-count:${mode==='scroll'?'auto':columns}!important;column-gap:${2*p.margin}px!important;column-fill:auto!important}p,li,div,span,td,th,blockquote,figcaption{font-size:inherit!important}p{max-width:${p.width/columns}px!important;margin-inline:auto!important;margin-top:0!important;margin-bottom:${p.paragraph_spacing}px!important}h1{font-size:1.5em!important}h2{font-size:1.25em!important}img{max-width:100%!important;max-height:${Math.max(80,innerHeight-2*p.margin)}px!important;height:auto!important;object-fit:contain!important;break-inside:avoid!important}a{color:${dim?'#d4a083':'#9f654b'}!important}`;
      globalThis.readerPhase=4;
      const fonts=await Promise.race([document.fonts.ready.then(()=>true),new Promise(r=>setTimeout(()=>r(false),1500))]);
      await new Promise(r=>{requestAnimationFrame(r);setTimeout(r,120);});globalThis.readerPhase=5;
      if(ticket!==layoutTicket)return before;
      if(!fonts&&!waitingForFonts){waitingForFonts=true;document.fonts.ready.then(()=>{waitingForFonts=false;if(prefs)configure(prefs,systemDark);});}
      const a=before.segments[0];restore({block_id:a.block,start:a.start,end:a.end,exact:a.exact});reflow=false;retained=a;globalThis.readerPhase=6;
      return before;
    };
    const layout=async(size,dark)=>{
      const selected=capture();await configure({version:1,layout:mode,font:'song',theme:'app',size,line_height:1.9,paragraph_spacing:18,margin:24,width:900},dark);
      if(selected.kind==='selection'){
        const a=selected.segments[0],z=selected.segments[selected.segments.length-1];
        const r=document.createRange();r.setStart(spans.find(e=>e.getAttribute('data-rk')===a.block).firstChild,a.start);r.setEnd(spans.find(e=>e.getAttribute('data-rk')===z.block).firstChild,z.end);
        const s=getSelection();s.removeAllRanges();s.addRange(r);last=selected;
      }return selected;
    };
    const turn=delta=>{
      const before=mode==='scroll'?scrollY:scrollX,limit=mode==='scroll'?document.documentElement.scrollHeight-innerHeight:document.documentElement.scrollWidth-innerWidth;
      const target=mode==='scroll'?before+delta*innerHeight*.85:before+delta*innerWidth;
      if((delta<0&&before<=1)||(delta>0&&before>=limit-1))return {edge:delta,position:viewport()};
      if(mode==='scroll')scrollTo(0,Math.max(0,Math.min(limit,target)));else scrollTo(Math.max(0,Math.min(limit,target)),0);
      last=null;cursor=visible();return {edge:0,position:cursor};
    };
    let resizeTimer;
    addEventListener('scroll',()=>{if(!reflow&&performance.now()>suppressScrollUntil){cursor=visible();last=null;}},{passive:true});
    addEventListener('wheel',()=>{suppressScrollUntil=0;},{passive:true});
    addEventListener('pointerdown',()=>{suppressScrollUntil=0;},{passive:true});
    addEventListener('keydown',()=>{suppressScrollUntil=0;});
    addEventListener('resize',()=>{reflow=true;clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{if(prefs)configure(prefs,systemDark);},100);});
    const checkRanges=()=>{
      const sel=getSelection(),old=[];for(let i=0;i<sel.rangeCount;i++)old.push(sel.getRangeAt(i).cloneRange());
      const saved=last,tests=[];
      try{
        for(const root of [...document.querySelectorAll('p')].filter(e=>e.querySelectorAll('[data-rk]').length>1).slice(0,3)){
          const r=document.createRange();r.selectNodeContents(root);sel.removeAllRanges();sel.addRange(r);last=null;
          tests.push(capture());
        }
        const paragraphs=[...document.querySelectorAll('p')].filter(e=>e.querySelector('[data-rk]'));
        if(paragraphs.length>1){const r=document.createRange();r.setStartBefore(paragraphs[0]);r.setEndAfter(paragraphs[1]);sel.removeAllRanges();sel.addRange(r);last=null;tests.push(capture());}
      }finally{sel.removeAllRanges();for(const r of old)sel.addRange(r);last=saved;}
      return tests;
    };
    const anchorVisible=()=>{
      const a=retained,n=spans.find(e=>e.getAttribute('data-rk')===a?.block)?.firstChild;if(!n)return false;
      const r=document.createRange();r.setStart(n,a.start);r.setEnd(n,Math.min(n.length,a.start+(n.data.codePointAt(a.start)>65535?2:1)));
      return [...r.getClientRects()].some(b=>b.bottom>0&&b.top<innerHeight&&b.left>=-1&&b.right<=innerWidth+1);
    };
    globalThis.readerHost={capture,restore,layout,configure,viewport,turn,blocks,checkRanges,anchorVisible};
    globalThis.readerPhase=2;await layout(size,dark);globalThis.readerPhase=7;
    if(anchor)restore(anchor);
    globalThis.readerPhase=8;return {session,resource,blocks};
    """#

    static let checks = #"""
    await Promise.race([document.fonts.ready,new Promise(r=>setTimeout(r,1500))]);
    const images=[...document.images].map(i=>({loaded:i.complete&&i.naturalWidth>0,width:i.naturalWidth,height:i.naturalHeight}));
    const denied=await Promise.all(['https://example.invalid/reader-check','file:///etc/passwd','reader-book://other/r1','reader-book://'+location.host+'/r9999'].map(async url=>{try{await fetch(url);return false;}catch{return true;}}));
    return {session:location.host,resource:location.pathname.slice(1),blocks:readerHost.blocks,images,denied,
      retained_anchor_visible:readerHost.anchorVisible(),viewport:readerHost.viewport(),selection:readerHost.capture(),range_tests:readerHost.checkRanges(),ruby:!!document.querySelector('ruby rt'),font_count:document.fonts.size,fonts_loaded:[...document.fonts].every(f=>f.status==='loaded'),strong_color:document.querySelector('strong')?getComputedStyle(document.querySelector('strong')).color:null};
    """#
}
