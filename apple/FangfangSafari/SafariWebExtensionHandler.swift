import Foundation
import SafariServices

// Safari 查詞: the extension's native part. Nothing to do: the words are looked up in the extension's own files
// (background.js), and words saved in it go to the app through its 傳到 App button (fangfangcards://…). So it needs
// no shared folder with the app, and works however the app was installed (also with Sideloadly).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": true]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
