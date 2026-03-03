# AppleReviewMCP

MCP (Model Context Protocol) server for self-review before Apple App Review submission. It reads the Apple Review documentation stored in the repo (apple-review-mcp/docs) and exposes tools to list documents, fetch full text, search guidelines, and get a pre-submission checklist.

The documents are point-in-time snapshots; the official Apple developer and legal pages remain the source of truth.

## Requirements

- Swift 6.0+ (Xcode 16+)
- macOS 13.0+

## Document path

The server reads `.txt` files from a directory you specify via `APPLE_REVIEW_DOCS_PATH`. This repo includes a **docs/** folder with Apple Review document snapshots (App Store Review Guidelines, App Review - Distribute, Trademarks, HIG index, README). To use them when running from the cloned repo:

```bash
export APPLE_REVIEW_DOCS_PATH="$(pwd)/docs"
swift run AppleReviewMCPServer
```

If you use this MCP from another project, point `APPLE_REVIEW_DOCS_PATH` at that project's docs directory or at this repo's `docs/` path.

## Build

```bash
# From repo root
swift build --package-path AppleReviewMCP

# Release binary (faster startup when used as MCP command)
swift build -c release --package-path AppleReviewMCP
# Binary: AppleReviewMCP/.build/release/AppleReviewMCPServer
```

## Run locally

```bash
# From this repo (use included docs)
export APPLE_REVIEW_DOCS_PATH="$(pwd)/docs"
swift run AppleReviewMCPServer

# Or point to your own directory
export APPLE_REVIEW_DOCS_PATH="/path/to/your/apple-review-docs"
swift run AppleReviewMCPServer
```

## Tools

| Tool | Description | Arguments |
|------|-------------|-----------|
| `list_apple_review_docs` | List available documents (id, file, description). | None |
| `get_apple_review_document` | Return the full text of one document. | `document_id`: `app_store_guidelines`, `app_review_distribute`, `trademarks`, `hig_index`, `readme` |
| `search_apple_review_guidelines` | Search all documents for a keyword or phrase; returns matching excerpts. | `query` (required) |
| `get_pre_submission_checklist` | Return "Before You Submit" and "Avoiding common issues" excerpts for a quick self-check. | None |
| `critique_app_listing` | Check app store listing against guidelines (2.1, 2.3, 5.1); returns potential issues and excerpted guidelines. | Optional: `app_store_public_url`, `name`, `subtitle`, `description`, `keywords`, `whats_new`, `privacy_policy_url`, `support_url` |

### critique_app_listing

- **Public URL**: Pass `app_store_public_url` (e.g. `https://apps.apple.com/app/id6755741622`) to fetch the public App Store page and extract title/description from meta tags. App Store Connect dashboard URLs (appstoreconnect.apple.com) require login and cannot be used.
- **Manual input**: You can instead (or in addition) pass `name`, `description`, `privacy_policy_url`, `support_url`, etc. Manual values override any fetched from the URL.
- **Note**: The critique is heuristic and does not guarantee App Review approval or rejection. Use it as a pre-submission aid alongside `get_pre_submission_checklist`.

## Cursor configuration

Add to `.cursor/mcp.json` under `mcpServers`:

```json
"apple-review-mcp": {
  "command": "/path/to/apple-review-mcp-clone/.build/release/AppleReviewMCPServer",
  "env": {
    "APPLE_REVIEW_DOCS_PATH": "/path/to/apple-review-mcp-clone/docs"
  }
}
```

Or run via `swift run` from the repo with `APPLE_REVIEW_DOCS_PATH` set to the repo's `docs/` directory.
