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

The objects served from `SPARKLE_PUBLIC_BASE_URL` must permit anonymous
`s3:GetObject` reads. Prefer a narrowly scoped bucket policy (or a public CDN)
instead of object ACLs. For the default bucket layout, make only the appcast
and `PlayStatus`-named update artifacts (full archives, release notes, and
delta updates) public:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadSparkleUpdates",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::com.bolar.playstatus/appcast.xml",
        "arn:aws:s3:::com.bolar.playstatus/PlayStatus*"
      ]
    }
  ]
}
```

Ensure the bucket's Block Public Access settings permit this policy. The
workflow probes the public appcast URL after publishing and fails if it is not
reachable.

Use a Team App Store Connect API key that can submit notarizations. Configure
the AWS IAM role for GitHub Actions OIDC with only `ListBucket`, `GetObject`,
and `PutObject` permissions on the Sparkle bucket; do not use
long-lived AWS access keys. The role trust policy must be restricted to this
repository and the `release` environment.

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

1. Update the marketing and build versions, then build and test locally as
   appropriate. Commit and push the source changes to `master`.
2. Create an annotated tag with a concise Markdown body. Its body becomes both
   the GitHub Release notes and the Sparkle HTML notes; no versioned note file
   is committed to the repository:

   ```sh
   git tag -a vX.Y.Z -m "PlayStatus X.Y.Z" -m $'- Added a useful feature\n- Fixed a user-visible issue'
   git push origin vX.Y.Z
   ```

   The tag body is required for a new release. Use plain paragraphs and `-`
   bullets; CI escapes and renders them into a minimal Sparkle-compatible HTML
   document that is retained only in the Sparkle bucket.

3. Do not create or commit `RELEASE_NOTES_X.Y.Z.html` files. Existing
   published Sparkle notes remain in S3 for historical update entries.
4. Approve the `release` environment. The workflow archives a universal app,
   notarizes and staples it, verifies it, creates the GitHub Release, publishes
   Sparkle payloads/appcast, and opens the vendor-tap cask pull request.
5. Merge the tap PR only after its macOS cask audit and install/uninstall check
   pass. Verify the published cask on clean Apple Silicon and Intel machines.

If a tagged release fails before it creates a GitHub Release, correct the
workflow on `main` and use its manual dispatch with the existing annotated tag.
The workflow still verifies that tag remotely before it can publish anything;
never delete or retarget a published release tag.

Release ZIPs, GitHub Release assets, and existing tags are immutable. If any
post-release issue is discovered, publish a new version and build number rather
than replacing an asset or retagging a release.
