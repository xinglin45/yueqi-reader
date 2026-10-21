import Foundation
import CoreFoundation

enum NativeTextCodec {
  enum Invalid: Error { case encoding }
  static func preview(_ data: Data, encoding: String) throws -> String {
    guard ["gb18030", "big5"].contains(encoding) else { throw Invalid.encoding }
    let cf = CFStringConvertIANACharSetNameToEncoding(encoding as CFString)
    guard cf != kCFStringEncodingInvalidId else { throw Invalid.encoding }
    let ns = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    guard let text = String(data: data, encoding: ns), !text.contains("\0"),
          let roundtrip = text.data(using: ns, allowLossyConversion: false), roundtrip == data else { throw Invalid.encoding }
    return String(text.prefix(2000))
  }
}
