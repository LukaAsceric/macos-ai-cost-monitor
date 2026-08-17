# Security Policy

## Supported versions

Only the latest published release is supported with security fixes.

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability.

Email the maintainer listed on the GitHub profile, or use GitHub's private
security advisory flow for this repository. Include:

- affected release or commit
- macOS version and architecture
- reproducible steps
- impact and any suggested mitigation

Do not include OpenRouter management keys or other secrets in a report.

The application stores the OpenRouter management key in macOS Keychain. It
must never be placed in issues, logs, screenshots, pull requests, or release
artifacts.
