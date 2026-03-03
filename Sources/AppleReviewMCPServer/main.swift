import Foundation
import MCP

// MARK: - Document store (loaded from APPLE_REVIEW_DOCS_PATH)

struct AppleReviewDocStore {
    static let documentIDs: [(id: String, file: String, description: String)] = [
        ("app_store_guidelines", "AppStoreReviewGuidelines.txt", "App Store Review Guidelines (Safety, Performance, Business, Design, Legal)"),
        ("app_review_distribute", "AppReview-Distribute.txt", "App Review hub: preparing, submitting, common issues, contacting"),
        ("trademarks", "GuidelinesForUsingAppleTrademarksAndCopyrights.txt", "Guidelines for Using Apple Trademarks and Copyrights"),
        ("hig_index", "HumanInterfaceGuidelines-Index.txt", "Human Interface Guidelines index (official URL only)"),
        ("readme", "README.txt", "Source URLs and collection date for all documents"),
    ]

    let basePath: String
    private var cache: [String: String] = [:]

    init?(basePath: String?) {
        guard let path = basePath, !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        self.basePath = path
    }

    mutating func loadAll() -> [String] {
        var errors: [String] = []
        for item in Self.documentIDs {
            let url = URL(fileURLWithPath: basePath).appendingPathComponent(item.file)
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                errors.append("Could not read: \(item.file)")
                continue
            }
            cache[item.id] = text
        }
        return errors
    }

    func getDocument(id: String) -> String? { cache[id] }

    func search(query: String) -> [(documentId: String, excerpt: String)] {
        let q = query.lowercased()
        var results: [(String, String)] = []
        for item in Self.documentIDs {
            guard let text = cache[item.id] else { continue }
            let lines = text.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                guard line.lowercased().contains(q) else { continue }
                let start = max(0, idx - 1)
                let end = min(lines.count, idx + 2)
                let excerpt = lines[start..<end].joined(separator: "\n")
                results.append((item.id, excerpt))
                if results.count >= 30 { return results }
            }
        }
        return results
    }

    func getPreSubmissionChecklist() -> String {
        var out: [String] = []
        out.append("=== Pre-submission checklist (from local Apple Review docs snapshot) ===\n")
        out.append("These are point-in-time excerpts. For the latest rules, refer to the official Apple pages.\n")

        if let guidelines = cache["app_store_guidelines"] {
            if let range = extractSection(guidelines, from: "### Before You Submit", to: "### 1. Safety") {
                out.append("\n--- Before You Submit (App Store Review Guidelines) ---\n")
                out.append(String(guidelines[range]))
            }
        }

        if let distribute = cache["app_review_distribute"] {
            if let range = extractSection(distribute, from: "## Avoiding common issues", to: "## Contacting us") {
                out.append("\n--- Avoiding common issues (App Review - Distribute) ---\n")
                out.append(String(distribute[range]))
            }
        }

        return out.joined(separator: "\n")
    }

    private func extractSection(_ text: String, from startMark: String, to endMark: String) -> Range<String.Index>? {
        guard let startRange = text.range(of: startMark),
              let endRange = text.range(of: endMark, range: startRange.upperBound..<text.endIndex) else { return nil }
        return startRange.lowerBound..<endRange.lowerBound
    }
}

// MARK: - App listing critique (fetch, parse, rules)

struct AppListingMetadata {
    var name: String?
    var subtitle: String?
    var description: String?
    var keywords: String?
    var whatsNew: String?
    var privacyPolicyURL: String?
    var supportURL: String?
}

func fetchAppStorePage(urlString: String) async -> String? {
    guard let url = URL(string: urlString),
          url.host?.contains("apps.apple.com") == true else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10
    guard let (data, _) = try? await URLSession.shared.data(for: request),
          let html = String(data: data, encoding: .utf8) else { return nil }
    return html
}

func parseMetaFromHTML(_ html: String) -> AppListingMetadata {
    func extractContent(from html: String, property: String) -> String? {
        let patterns = [
            "<meta property=\"\(property)\" content=\"([^\"]+)\"",
            "<meta name=\"\(property)\" content=\"([^\"]+)\"",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                var s = String(html[range])
                s = s.replacingOccurrences(of: "&amp;", with: "&")
                s = s.replacingOccurrences(of: "&lt;", with: "<")
                s = s.replacingOccurrences(of: "&gt;", with: ">")
                s = s.replacingOccurrences(of: "&quot;", with: "\"")
                return s
            }
        }
        return nil
    }
    var meta = AppListingMetadata()
    meta.name = extractContent(from: html, property: "og:title")
    meta.description = extractContent(from: html, property: "og:description")
    if meta.description == nil { meta.description = extractContent(from: html, property: "description") }
    return meta
}

func runCritique(metadata: AppListingMetadata, store: AppleReviewDocStore) -> String {
    var issues: [String] = []
    let desc = (metadata.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let name = (metadata.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let placeholderPatterns = ["lorem", "ipsum", "test", "xxx", "tbd", "todo", "sample", "placeholder"]
    func hasPlaceholder(_ s: String) -> Bool {
        let lower = s.lowercased()
        return placeholderPatterns.contains { lower.contains($0) }
    }

    if desc.isEmpty {
        issues.append("Description is empty. Guideline 2.1 / 2.3 require complete and accurate metadata.")
    } else if desc.count < 50 {
        issues.append("Description is very short (\(desc.count) chars). Consider a clear, complete description for Guideline 2.1 / 2.3.")
    }
    if hasPlaceholder(desc) || hasPlaceholder(name) {
        issues.append("Placeholder-like text (e.g. lorem, test, xxx, TBD) detected in name or description. Guideline 2.1: remove placeholder content before submission.")
    }
    let hasPrivacyURL = (metadata.privacyPolicyURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let descMentionsPrivacy = desc.lowercased().contains("privacy")
    if !hasPrivacyURL && !descMentionsPrivacy {
        issues.append("No privacy policy URL provided and description does not mention privacy. Guideline 5.1 and App Review require a privacy policy link for all apps.")
    }
    let hasSupportURL = (metadata.supportURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    if !hasSupportURL {
        issues.append("No support URL provided. App Review requires a link to user support with up-to-date contact information.")
    }

    var guidelineExcerpts: [String] = []
    for term in ["privacy policy", "support", "placeholder", "metadata", "2.1", "5.1"] {
        let results = store.search(query: term)
        for r in results.prefix(2) {
            guidelineExcerpts.append("[\(r.documentId)] \(r.excerpt)")
        }
    }
    let excerptBlock = guidelineExcerpts.isEmpty ? "" : "\n\n--- Relevant guideline excerpts ---\n\n" + guidelineExcerpts.joined(separator: "\n\n")

    if issues.isEmpty {
        return "No obvious issues detected for the provided listing. Use get_pre_submission_checklist for a full pre-submission checklist."
        + excerptBlock
    }
    var out = "Potential issues (heuristic check; not a guarantee of approval or rejection):\n\n"
    for (i, issue) in issues.enumerated() { out += "\(i + 1). \(issue)\n" }
    return out + excerptBlock
}

// MARK: - Resolve docs path

func resolveDocsPath() -> String? {
    if let env = ProcessInfo.processInfo.environment["APPLE_REVIEW_DOCS_PATH"], !env.isEmpty {
        return (env as NSString).expandingTildeInPath
    }
    let cwd = FileManager.default.currentDirectoryPath
    let relative = "TranslateBluePackage/Sources/TranslateBlueFeature/Legal/AppleReview"
    let candidate = (cwd as NSString).appendingPathComponent(relative)
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
        return candidate
    }
    return nil
}

// MARK: - Server and tools

let server = Server(
    name: "AppleReviewMCP",
    version: "1.0.0",
    title: "Apple Review MCP Server",
    capabilities: .init(tools: .init(listChanged: false))
)

let toolListDocs = Tool(
    name: "list_apple_review_docs",
    description: "List available Apple Review documents (id, file, short description). Documents are local snapshots; official Apple pages are the source of truth.",
    inputSchema: .object([
        "type": .string("object"),
    ])
)

let toolGetDocument = Tool(
    name: "get_apple_review_document",
    description: "Return the full text of one document. Use document_id: app_store_guidelines, app_review_distribute, trademarks, hig_index, or readme.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "document_id": .object(["type": .string("string"), "description": .string("One of: app_store_guidelines, app_review_distribute, trademarks, hig_index, readme")]),
        ]),
        "required": .array([.string("document_id")]),
    ])
)

let toolSearch = Tool(
    name: "search_apple_review_guidelines",
    description: "Search all Apple Review documents for a keyword or phrase; returns matching excerpts.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "query": .object(["type": .string("string"), "description": .string("Search string")]),
        ]),
        "required": .array([.string("query")]),
    ])
)

let toolChecklist = Tool(
    name: "get_pre_submission_checklist",
    description: "Return a pre-submission checklist: Before You Submit and Avoiding common issues (excerpts from App Store Review Guidelines and App Review - Distribute).",
    inputSchema: .object([
        "type": .string("object"),
    ])
)

let toolCritique = Tool(
    name: "critique_app_listing",
    description: "Check app store listing against Apple Review guidelines (2.1, 2.3, 5.1). Pass app_store_public_url (e.g. https://apps.apple.com/app/id6755741622) and/or manual fields (name, subtitle, description, keywords, whats_new, privacy_policy_url, support_url). Returns potential issues and guideline excerpts.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "app_store_public_url": .object(["type": .string("string"), "description": .string("Public App Store page URL (apps.apple.com/...)")]),
            "name": .object(["type": .string("string"), "description": .string("App name")]),
            "subtitle": .object(["type": .string("string"), "description": .string("Subtitle")]),
            "description": .object(["type": .string("string"), "description": .string("App description")]),
            "keywords": .object(["type": .string("string"), "description": .string("Keywords")]),
            "whats_new": .object(["type": .string("string"), "description": .string("What's New text")]),
            "privacy_policy_url": .object(["type": .string("string"), "description": .string("Privacy policy URL")]),
            "support_url": .object(["type": .string("string"), "description": .string("Support URL")]),
        ]),
        "required": .array([]),
    ])
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: [toolListDocs, toolGetDocument, toolSearch, toolChecklist, toolCritique])
}

var docStore: AppleReviewDocStore?
if let path = resolveDocsPath() {
    var store = AppleReviewDocStore(basePath: path)!
    let loadErrors = store.loadAll()
    if !loadErrors.isEmpty {
        fputs("AppleReviewMCP warning: \(loadErrors.joined(separator: "; "))\n", stderr)
        try? FileHandle.standardError.synchronize()
    }
    docStore = store
} else {
    fputs("AppleReviewMCP: APPLE_REVIEW_DOCS_PATH not set and default path not found. Tools will return an error.\n", stderr)
    try? FileHandle.standardError.synchronize()
}

let loadedStore = docStore
await server.withMethodHandler(CallTool.self) { params in
    guard let store = loadedStore else {
        return CallTool.Result(
            content: [.text("Error: Document path not configured. Set APPLE_REVIEW_DOCS_PATH to the Legal/AppleReview directory.")],
            isError: true
        )
    }

    switch params.name {
    case "list_apple_review_docs":
        let lines = AppleReviewDocStore.documentIDs.map { "\($0.id): \($0.file) - \($0.description)" }
        let note = "Documents are snapshots; refer to official Apple pages for the latest."
        return CallTool.Result(content: [.text([lines.joined(separator: "\n"), note].joined(separator: "\n\n"))], isError: false)

    case "get_apple_review_document":
        let id = params.arguments?["document_id"]?.stringValue ?? ""
        guard AppleReviewDocStore.documentIDs.contains(where: { $0.id == id }) else {
            return CallTool.Result(
                content: [.text("Error: Invalid document_id. Use one of: app_store_guidelines, app_review_distribute, trademarks, hig_index, readme.")],
                isError: true
            )
        }
        if let text = store.getDocument(id: id) {
            return CallTool.Result(content: [.text(text)], isError: false)
        }
        return CallTool.Result(content: [.text("Error: Document not loaded.")], isError: true)

    case "search_apple_review_guidelines":
        let query = params.arguments?["query"]?.stringValue ?? ""
        guard !query.isEmpty else {
            return CallTool.Result(content: [.text("Error: query is required.")], isError: true)
        }
        let results = store.search(query: query)
        if results.isEmpty {
            return CallTool.Result(content: [.text("No matches found for \"\(query)\".")], isError: false)
        }
        let output = results.map { "[\($0.documentId)]\n\($0.excerpt)" }.joined(separator: "\n\n---\n\n")
        return CallTool.Result(content: [.text(output)], isError: false)

    case "get_pre_submission_checklist":
        return CallTool.Result(content: [.text(store.getPreSubmissionChecklist())], isError: false)

    case "critique_app_listing":
        let args = params.arguments ?? [:]
        let urlString = args["app_store_public_url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        var meta = AppListingMetadata(
            name: args["name"]?.stringValue,
            subtitle: args["subtitle"]?.stringValue,
            description: args["description"]?.stringValue,
            keywords: args["keywords"]?.stringValue,
            whatsNew: args["whats_new"]?.stringValue,
            privacyPolicyURL: args["privacy_policy_url"]?.stringValue,
            supportURL: args["support_url"]?.stringValue
        )
        if let urlString = urlString, !urlString.isEmpty {
            if let html = await fetchAppStorePage(urlString: urlString) {
                let fromPage = parseMetaFromHTML(html)
                if meta.name == nil { meta.name = fromPage.name }
                if meta.description == nil { meta.description = fromPage.description }
            }
        }
        let hasAnyInput = urlString != nil || meta.name != nil || meta.description != nil || meta.privacyPolicyURL != nil || meta.supportURL != nil
        guard hasAnyInput else {
            return CallTool.Result(
                content: [.text("Error: Provide app_store_public_url (e.g. https://apps.apple.com/app/id6755741622) and/or at least one of: name, description, privacy_policy_url, support_url.")],
                isError: true
            )
        }
        return CallTool.Result(content: [.text(runCritique(metadata: meta, store: store))], isError: false)

    default:
        return CallTool.Result(content: [.text("Unknown tool: \(params.name)")], isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
