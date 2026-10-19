#if DEBUG
// MAC-06 probe only. Not registered in Release and not a general browser bridge.
import Cocoa
import FlutterMacOS
import WebKit

final class Mac06Factory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        Mac06WebView(viewId: viewId, messenger: messenger, args: args as? [String: Any] ?? [:])
    }
}
final class Mac06Scheme: NSObject, WKURLSchemeHandler {
    let host: String
    let resources: [String: [String: Any]]
    var rejected = 0
    var served = [String]()
    init(host: String, resources: [String: [String: Any]]) { self.host = host; self.resources = resources }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "reader-probe", url.host == host,
              !url.path.contains(".."), !url.path.contains("\\"), url.query == nil,
              let item = resources[String(url.path.dropFirst())],
              let base64 = item["base64"] as? String, let data = Data(base64Encoded: base64),
              data.count <= 4_000_000 else {
            rejected += 1; urlSchemeTask.didFailWithError(NSError(domain:"Mac06Resource",code:403)); return
        }
        served.append(String(url.path.dropFirst()))
        urlSchemeTask.didReceive(URLResponse(url:url,mimeType:item["mime"] as? String,expectedContentLength:data.count,textEncodingName:"utf-8"))
        urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
final class Mac06WebView: NSView, WKNavigationDelegate {
    let channel: FlutterMethodChannel
    let scheme: Mac06Scheme
    let web: WKWebView
    var ready = false
    var blockedNavigations = 0
    var alive = true
    init(viewId: Int64, messenger: FlutterBinaryMessenger, args: [String: Any]) {
        let host = "b" + String((args["revision"] as? String ?? "invalid").prefix(32))
        scheme = Mac06Scheme(host:host,resources: args["resources"] as? [String: [String: Any]] ?? [:])
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(scheme, forURLScheme:"reader-probe")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Book scripts are absent after sanitization and CSP forbids execution.
        // Only host-owned, isolated-world code is evaluated below.
        web = WKWebView(frame:.zero,configuration:config)
        channel = FlutterMethodChannel(name:"mac06/webview/\(viewId)",binaryMessenger:messenger)
        super.init(frame:.zero)
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false; addSubview(web)
        NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo:topAnchor),web.bottomAnchor.constraint(equalTo:bottomAnchor),web.leadingAnchor.constraint(equalTo:leadingAnchor),web.trailingAnchor.constraint(equalTo:trailingAnchor)])
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self, self.alive else { result(FlutterError(code:"disposed",message:nil,details:nil)); return }
            let params = call.arguments as? [String:Any] ?? [:]
            if call.method == "status" { result(self.ready); return }
            if call.method == "navigate", let path = params["path"] as? String, self.scheme.resources[path] != nil {
                self.ready = false
                self.web.load(URLRequest(url:URL(string:"reader-probe://\(self.scheme.host)/\(path)")!)); result(true); return
            }
            if call.method == "checks", self.ready {
                self.web.callAsyncJavaScript(Self.checks, arguments:[:],in:nil,in:.defaultClient) { [weak self] value in
                    guard let self=self,self.alive else { result(FlutterError(code:"disposed",message:nil,details:nil));return }
                    switch value {
                    case .success(let data):
                        self.web.callAsyncJavaScript("return globalThis.untrustedBookExecuted === true;",arguments:[:],in:nil,in:.page) { page in
                            let executed: Any
                            switch page { case .success(let flag): executed = flag; case .failure: executed = NSNull() }
                            result(["dom":data,"book_page_script_executed":executed,"resource_denied":self.scheme.rejected,"served":Array(Set(self.scheme.served)).sorted(),"blocked_navigations":self.blockedNavigations])
                        }
                    case .failure: result(FlutterError(code:"dom_check_failed",message:nil,details:nil))
                    }
                };return
            }
            result(FlutterError(code:"not_ready_or_unsupported",message:nil,details:nil))
        }
        let rules="""
        [{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier:"local.yueqi.mac06.block-network",encodedContentRuleList:rules) { [weak self] list, error in
            guard let self=self else { return }
            guard let list=list,error == nil else { NSLog("MAC06_NATIVE rule_compile_failed"); return }
            NSLog("MAC06_NATIVE loading resources=%d", self.scheme.resources.count)
            self.web.configuration.userContentController.add(list)
            guard let path=args["path"] as? String,self.scheme.resources[path] != nil else { return }
            self.web.load(URLRequest(url:URL(string:"reader-probe://\(self.scheme.host)/\(path)")!))
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    deinit { alive=false; web.stopLoading(); channel.setMethodCallHandler(nil) }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { NSLog("MAC06_NATIVE provisional_error=%d", (error as NSError).code) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { NSLog("MAC06_NATIVE navigation_error=%d", (error as NSError).code) }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { NSLog("MAC06_NATIVE webprocess_terminated") }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) { ready=true;channel.invokeMethod("ready",arguments:nil) }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url,url.scheme=="reader-probe",url.host==scheme.host,scheme.resources[String(url.path.dropFirst())] != nil else {
            blockedNavigations += 1;decisionHandler(.cancel);return
        }
        decisionHandler(.allow)
    }
    // Fixed trusted code, never taken from the EPUB. UTF-16 matches JS/NSRange/Dart.
    static let checks = #"""
    await document.fonts.ready;
    const ignored = new Set(['SCRIPT','STYLE','RT','RP']);
    const visibleNodes = root => {
      if(root.getAttribute('aria-hidden')==='true')return [];const nodes=[];const walk=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
      while(walk.nextNode()) {let p=walk.currentNode.parentElement,ok=true;while(p&&p!==root){if(ignored.has(p.localName.toUpperCase())||p.getAttribute('aria-hidden')==='true'){ok=false;break;}p=p.parentElement;}if(ok)nodes.push(walk.currentNode);}
      return nodes;
    };
    const textOf = el=>visibleNodes(el).map(n=>n.data).join('');
    const captureSelection=()=>{
      const sel=window.getSelection();if(!sel.rangeCount||sel.isCollapsed)return null;
      const r=sel.getRangeAt(0);const first=r.startContainer.nodeType===3?r.startContainer.parentElement:r.startContainer;
      const block=first.closest('p,h1,h2,blockquote');if(!block)return {unsupported:'outside_block'};
      let cursor=0,start=null,end=null;for(const n of visibleNodes(block)){if(n===r.startContainer)start=cursor+r.startOffset;if(n===r.endContainer)end=cursor+r.endOffset;cursor+=n.length;}
      if(start===null||end===null)return {unsupported:'cross_block_or_element_boundary'};
      return {block_id:block.id,start_utf16:start,end_utf16:end,exact:textOf(block).slice(start,end),visual:sel.toString()};
    };
    if(!globalThis.mac06SelectionObserver){
      document.addEventListener('selectionchange',()=>{const anchor=captureSelection();if(anchor)globalThis.mac06LastSelection=anchor;});
      globalThis.mac06SelectionObserver=true;
    }
    const userSelection=captureSelection()||globalThis.mac06LastSelection||null;
    const blocks=[...document.querySelectorAll('h1,h2,p,blockquote')].map(el=>({id:el.id,text:textOf(el),utf16_length:textOf(el).length}));
    const target=document.getElementById('target')||document.getElementById('p2');
    const all=textOf(target);const word=all.includes('目标位置')?'目标位置':'雨后山路';
    const start=all.indexOf(word),end=start+word.length;
    const locate=offset=>{let left=offset;for(const n of visibleNodes(target)){if(left<=n.length)return [n,left];left-=n.length;}throw Error('offset');};
    const makeRange=()=>{const [a,x]=locate(start),[b,y]=locate(end);const r=document.createRange();r.setStart(a,x);r.setEnd(b,y);return r;};
    const range=makeRange();const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);
    const selected=selection.toString();
    const highlightsSupported=typeof CSS.highlights!=='undefined';
    if(highlightsSupported){CSS.highlights.set('probe',new Highlight(range));const style=document.createElementNS(document.documentElement.namespaceURI,'style');style.textContent='::highlight(probe){background:#e6c9a8;color:#2d2925}';document.head.append(style);}
    const anchor={block_id:target.id,start_utf16:start,end_utf16:end,exact:selected};
    const restorations=[];const body=document.body;
    for(const [width,columns,size] of [['360px','1','26px'],['740px','2','21px'],['auto','1','23px']]) {
      body.style.width=width;body.style.columnCount=columns;body.style.fontSize=size;
      await new Promise(requestAnimationFrame); const restored=makeRange();const rect=restored.getBoundingClientRect();
      restorations.push({width,columns,exact:restored.toString(),finite_rect:Number.isFinite(rect.left)&&rect.height>0});
    }
    body.style.width='auto';body.style.columnCount='1';body.style.fontSize='23px';
    const strong=document.querySelector('strong'),quote=document.querySelector('blockquote');
    const css={strong_color:strong?getComputedStyle(strong).color:null,blockquote_border:quote?getComputedStyle(quote).borderLeftWidth:null,ruby:!!document.querySelector('ruby rt'),embedded_font:document.fonts.check('16px ProbeIcon')};
    const image=document.querySelector('img');
    const img={present:!!image,loaded:image?image.complete&&image.naturalWidth===96:null};
    // Trusted negative tests exercise the same CSP/resource broker, with no external data.
    const tries=await Promise.all(['https://example.invalid/mac06','file:///etc/passwd','reader-probe://other-book/private','reader-probe://'+location.host+'/not-in-manifest'].map(async url=>{try{await fetch(url);return {kind:url.split(':')[0],blocked:false};}catch{return {kind:url.split(':')[0],blocked:true};}}));
    selection.removeAllRanges();selection.addRange(makeRange());
    return {path:location.pathname.slice(1),user_selection:userSelection,blocks,anchor,selected,restorations,css,image:img,highlights_supported:highlightsSupported,resource_tests:tries,book_script_executed:window.untrustedBookExecuted===true,offset_unit:'utf16_code_unit'};
    """#
}
#endif
