# AppleReviewMCP

MCP (Model Context Protocol) server for self-review before Apple App Review submission. It reads the Apple Review documentation stored in the repo (Legal/AppleReview) and exposes tools to list documents, fetch full text, search guidelines, and get a pre-submission checklist.

The documents are point-in-time snapshots; the official Apple developer and legal pages remain the source of truth.

## Requirements

- Swift 6.0+ (Xcode 16+)
- macOS 13.0+

## Document path

The server reads `.txt` files from the **Legal/AppleReview** directory. Set `APPLE_REVIEW_DOCS_PATH` to that directory if you run the server from a different working directory. The script `Scripts/run-apple-review-mcp.sh` sets it automatically from the repo root.

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
# From repo root (sets APPLE_REVIEW_DOCS_PATH and runs the server)
./Scripts/run-apple-review-mcp.sh

# Or with explicit path
export APPLE_REVIEW_DOCS_PATH="/path/to/TranslateBluePackage/Sources/TranslateBlueFeature/Legal/AppleReview"
swift run --package-path AppleReviewMCP AppleReviewMCPServer
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

The project adds this server in [.cursor/mcp.json](../.cursor/mcp.json) as `apple-review-mcp`, using `Scripts/run-apple-review-mcp.sh`. No environment variables are required if you use that script (it sets `APPLE_REVIEW_DOCS_PATH`). To override the docs path, add an `env` block for this server with `APPLE_REVIEW_DOCS_PATH`.

To use the release binary instead of the script (faster startup), set the server command to the full path of `AppleReviewMCP/.build/release/AppleReviewMCPServer` and set `APPLE_REVIEW_DOCS_PATH` in the server env to the Legal/AppleReview directory path.
