import Foundation

// Snippet XML import/export (SnippetEditorController.m
// :742-814 parse, :992-1072 export; constants.h:79-88). Schema (version 1.0,
// UTF-8), <content> preserves whitespace:
//
//   <folders>
//     <folder>
//       <title>Folder</title>
//       <snippets>
//         <snippet><title>Name</title><content>Body</content></snippet>
//       </snippets>
//     </folder>
//   </folders>

struct ParsedSnippet: Sendable {
    let title: String
    let content: String
}

struct ParsedFolder: Sendable {
    let title: String
    let snippets: [ParsedSnippet]
}

enum SnippetXML {
    static let fileExtension = "xml"          // constants.h:79 kXMLFileType
    static let defaultExportName = "snippets" // SnippetEditorController.m:23

    // Element names (constants.h:83-88).
    private static let root = "folders"
    private static let folder = "folder"
    private static let snippets = "snippets"
    private static let snippet = "snippet"
    private static let title = "title"
    private static let content = "content"

    /// Build the export document, folders and snippets sorted by index by the
    /// caller (exportSnippets:, SnippetEditorController.m:992-1072).
    static func export(folders: [(title: String, snippets: [(title: String, content: String)])]) -> Data {
        let rootElement = XMLElement(name: root)
        for f in folders {
            let folderElement = XMLElement(name: folder)
            folderElement.addChild(XMLElement(name: title, stringValue: xmlSafe(f.title)))
            let snippetsElement = XMLElement(name: snippets)
            for s in f.snippets {
                let snippetElement = XMLElement(name: snippet)
                snippetElement.addChild(XMLElement(name: title, stringValue: xmlSafe(s.title)))
                // Preserve whitespace in content (NSXMLNodePreserveWhitespace).
                let contentElement = XMLElement(kind: .element, options: .nodePreserveWhitespace)
                contentElement.name = content
                contentElement.stringValue = xmlSafe(s.content)
                snippetElement.addChild(contentElement)
                snippetsElement.addChild(snippetElement)
            }
            folderElement.addChild(snippetsElement)
            rootElement.addChild(folderElement)
        }
        let document = XMLDocument(rootElement: rootElement)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return document.xmlData(options: .nodePrettyPrint)
    }

    /// Strip Unicode scalars that are illegal in XML 1.0 (XMLElement escapes
    /// &<> but emits C0 control bytes verbatim, producing a document that
    /// XMLDocument(data:) later refuses to parse — i.e. an unreadable backup).
    /// Valid: #x9 #xA #xD, #x20–#xD7FF, #xE000–#xFFFD, #x10000–#x10FFFF.
    private static func xmlSafe(_ string: String) -> String {
        func isValid(_ u: Unicode.Scalar) -> Bool {
            switch u.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                return true
            default:
                return false
            }
        }
        guard string.unicodeScalars.contains(where: { !isValid($0) }) else { return string }
        var scalars = String.UnicodeScalarView()
        for u in string.unicodeScalars where isValid(u) { scalars.append(u) }
        return String(scalars)
    }

    /// Parse an exported document back into folders (parser delegate,
    /// SnippetEditorController.m:742-814). Unknown/missing fields default to "".
    static func parse(_ data: Data) -> [ParsedFolder] {
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]),
              let rootElement = document.rootElement(), rootElement.name == root
        else { return [] }

        return rootElement.elements(forName: folder).map { folderElement in
            let folderTitle = folderElement.elements(forName: title).first?.stringValue ?? ""
            let snippetEls = folderElement.elements(forName: snippets).first?
                .elements(forName: snippet) ?? []
            let parsedSnippets = snippetEls.map { el in
                ParsedSnippet(
                    title: el.elements(forName: title).first?.stringValue ?? "",
                    content: el.elements(forName: content).first?.stringValue ?? ""
                )
            }
            return ParsedFolder(title: folderTitle, snippets: parsedSnippets)
        }
    }
}
