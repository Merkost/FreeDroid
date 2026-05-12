import Foundation

let delegate = BridgeService()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
