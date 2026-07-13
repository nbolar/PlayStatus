# Releasing PlayStatus

The `Release PlayStatus` workflow runs only for an annotated `vX.Y.Z` tag. It
will reject a tag that does not exactly match the app's `MARKETING_VERSION`.
`CURRENT_PROJECT_VERSION` must also be greater than every Sparkle build already
in the appcast, because Sparkle uses the bundle build number to order updates.

## One-time GitHub setup

Create a GitHub Environment named `release` and restrict it to trusted
maintainers. Add these environment secrets:

- `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APPSTORE_CONNECT_API_KEY_P8_BASE64`
- `SPARKLE_ED25519_PRIVATE_KEY` — the existing private key matching
  `SUPublicEDKey`; never generate a replacement key for an existing feed.
- `HOMEBREW_TAP_TOKEN` — a fine-grained token limited to contents and pull
  requests for `nbolar/homebrew-playstatus`.

Add these repository or environment variables:

- `APPLE_DEVELOPER_IDENTITY`
- `APPLE_TEAM_ID`
- `APPSTORE_CONNECT_KEY_ID`
- `APPSTORE_CONNECT_ISSUER_ID`
- `SPARKLE_S3_ROLE_ARN`
- `SPARKLE_S3_REGION`
- `SPARKLE_S3_URI` (for example, `s3://com.bolar.playstatus`)
- `SPARKLE_PUBLIC_BASE_URL` (the public HTTPS base for that bucket, with a
  trailing slash)

Use a Team App Store Connect API key that can submit notarizations. Configure
the AWS IAM role for GitHub Actions OIDC with only `ListBucket`, `GetObject`,
and `PutObject` permissions on the Sparkle bucket; do not use long-lived AWS
access keys. The role trust policy must be restricted to this repository and
the `release` environment.

## Bootstrap the vendor tap

After authenticating the GitHub CLI as `nbolar`, run:

```sh
gh auth login -h github.com
scripts/init-homebrew-tap.sh
```

This creates the public `nbolar/homebrew-playstatus` repository with its cask
validation workflow. The first successful PlayStatus release opens the pull
request that adds `Casks/playstatus.rb`.

## Release procedure

1. Update the marketing and build versions and add
   `RELEASE_NOTES_X.Y.Z.html` to the repository.
2. Build and test the release locally as appropriate, then commit the version
   and release-note changes.
3. Create and push an annotated tag: `git tag -a vX.Y.Z -m "PlayStatus X.Y.Z"`
   followed by `git push origin vX.Y.Z`.
4. Approve the `release` environment. The workflow archives a universal app,
   notarizes and staples it, verifies it, creates the GitHub Release, publishes
   Sparkle payloads/appcast, and opens the vendor-tap cask pull request.
5. Merge the tap PR only after its macOS cask audit and install/uninstall check
   pass. Verify the published cask on clean Apple Silicon and Intel machines.

Release ZIPs, GitHub Release assets, and existing tags are immutable. If any
post-release issue is discovered, publish a new version and build number rather
than replacing an asset or retagging a release.
