import Foundation
@main struct NativeCodecProbe {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    var results = [[String:Any]]()
    for (name,encoding,expected) in [("GB18030.txt","gb18030","这是自产的中文导入样本"),("Big5.txt","big5","這是自產的中文匯入樣本")] {
      let preview = try NativeTextCodec.preview(Data(contentsOf: root.appendingPathComponent(name)), encoding: encoding)
      guard preview.contains(expected), !preview.contains("�") else { fatalError("codec mismatch") }
      results.append(["file":name,"encoding":encoding,"exact_owned_text":true])
    }
    do { _ = try NativeTextCodec.preview(Data([0xff,0x81,0x00,0xfe]), encoding:"big5"); fatalError("invalid accepted") }
    catch NativeTextCodec.Invalid.encoding { results.append(["malformed_rejected":true]) }
    print(String(data:try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
  }
}
