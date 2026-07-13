import Combine
import Foundation

@MainActor
final class MarkdownTextBindingAdapter: ObservableObject {
    @Published private(set) var editorText: String
    private(set) var hasMarkedText = false

    init(text: String) {
        editorText = text
    }

    func receiveExternalText(_ text: String) {
        guard !hasMarkedText else { return }
        editorText = text
    }

    func receiveEditorText(_ text: String, writeBack: (String) -> Void) {
        editorText = text
        writeBack(text)
    }

    func setMarkedTextActive(_ isActive: Bool) {
        hasMarkedText = isActive
    }
}

enum MarkdownImageURLResolver {
    static func localURL(for path: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: path, relativeTo: baseURL), url.isFileURL {
            return url.standardizedFileURL
        }
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
