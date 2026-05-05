# Changelog

## [Unreleased]

### Added
- `Sync-EVAccessPackage` - reconciles access package assignments against auto-assignment policy filter
- `Get-EVAccessPackageDrift` - reports drift without making changes
- `Convert-PolicyFilterToGraphFilter` - private helper translating policy filter syntax to Graph OData
- `Invoke-MgGraphBatchGetAll` - private helper for batched Graph GET requests with pagination
