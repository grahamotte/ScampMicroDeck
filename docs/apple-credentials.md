# Apple credentials

`mise publish` signs and publishes Apple apps without using an Xcode login or certificates from the login keychain. Keep every value below in the deployment environment. For local publishing, that is the gitignored `.env.production` file.

## Repository-only macOS releases

Set `"skip_app_stores": true` in the `apps` section of `config.json` to publish only the macOS release to GitHub. The workflow still archives the app, signs it with Developer ID, notarizes and staples it, and uploads the installable zip to the repository. It skips App Store exports, uploads, metadata, screenshots, build attachment, and submission preparation.

Repository-only releases do not require the Apple Distribution or Mac Installer Distribution certificate variables. The Apple Development and Developer ID certificate variables, App Store Connect API key variables, Apple team ID, and GitHub credentials remain required for archiving, provisioning, notarization, and release uploads.

## App Review attachments

Add an optional `reviewAttachments` array to the `apps` section of `config.json` when App Review needs sample files, documentation, or videos to test the app:

```json
{
  "apps": {
    "reviewAttachments": [
      {
        "path": "apps/review/sample.zip"
      }
    ]
  }
}
```

Paths are resolved from the repository root. Publishing validates each file, uploads changed attachments to every configured Apple target's review details, removes attachments not listed in the configuration, and waits for App Store Connect to finish processing them before preparing the submission.

## Credentials

| Environment variable | Purpose | Normal rotation |
| --- | --- | --- |
| `APPLE_TEAM_ID` | Selects the Apple Developer team for archives, exports, profiles, and notarization. | Never, unless the app changes teams. |
| `APPLE_ISSUER_ID` | Identifies the issuer of the App Store Connect team API key. | Rotate with the API key if Apple supplies a different issuer. |
| `APPLE_KEY_ID` | Identifies the App Store Connect team API key. | Rotate with the API key. |
| `APPLE_KEY_SECRET_BASE64` | Base64-encoded `.p8` private key used for App Store Connect, Xcode provisioning, uploads, and notarization. | Rotate with the API key. |
| `APPLE_DEVELOPMENT_CERTIFICATE_BASE64` | Base64-encoded Apple Development identity used to create Xcode archives. | Before expiry or after private-key compromise. |
| `APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD` | Password for the Apple Development `.p12`. | Rotate with that `.p12`. |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution identity used for App Store exports and uploads. | Before expiry or after private-key compromise. |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the Apple Distribution `.p12`. | Rotate with that `.p12`. |
| `APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded Mac Installer Distribution identity used to package Mac App Store uploads. | Before expiry or after private-key compromise. |
| `APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the Mac Installer Distribution `.p12`. | Rotate with that `.p12`. |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application identity used for the standalone macOS release. | Before expiry or after private-key compromise. |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the Developer ID Application `.p12`. | Rotate with that `.p12`. |

The `.p12` values contain both the certificate and its private key. The API `.p8` is a separate authentication key and cannot sign an app.

## Current team and certificate inventory

Verify this identity before every rotation. Do not select a certificate belonging to an unrelated personal or work team.

- Team name: `GRAHAM ALLAN OTTE`
- Team ID: `3QCHM255VF`

As of August 2, 2026:

| Identity | Expires |
| --- | --- |
| Apple Development: Created via API | August 3, 2027 |
| Apple Distribution: GRAHAM ALLAN OTTE (`3QCHM255VF`) | June 4, 2027 |
| 3rd Party Mac Developer Installer: GRAHAM ALLAN OTTE (`3QCHM255VF`) | June 4, 2027 |
| Developer ID Application: GRAHAM ALLAN OTTE (`3QCHM255VF`) | February 1, 2027 |

Review these dates at least quarterly. Replace a credential before its expiry rather than during a release.

## Safety rules

1. Back up the current secret values in the secret manager used by the deployment environment.
2. Create and verify the replacement before revoking the old credential.
3. Change each base64 value and its password together. Change the API key ID and private key together.
4. Confirm every certificate subject contains `O=GRAHAM ALLAN OTTE` and `OU=3QCHM255VF`.
5. Never commit `.p8`, `.p12`, passwords, or populated environment files.
6. Use a new, unique password for every `.p12` export.

## Rotate the App Store Connect API key

The workflow needs a **team API key with Admin access**. Individual API keys do not support provisioning or `notarytool`.

1. Sign in to App Store Connect as the Account Holder or an Admin.
2. Open **Users and Access → Integrations → Team Keys**.
3. Create an Admin key and download its `AuthKey_<KEY_ID>.p8` file immediately. Apple permits the private key to be downloaded only once.
4. Copy the page's issuer ID and the new key ID.
5. Encode the downloaded key:

   ```sh
   base64 -i AuthKey_<KEY_ID>.p8
   ```

6. Update `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, and `APPLE_KEY_SECRET_BASE64` together.
7. Load the new environment and verify authentication without publishing:

   ```sh
   set -a
   source .env.production
   set +a
   key_file="$(mktemp)"
   trap 'rm -f "$key_file"' EXIT
   printf "%s" "$APPLE_KEY_SECRET_BASE64" | base64 -D > "$key_file"
   chmod 600 "$key_file"
   xcrun notarytool history --key "$key_file" --key-id "$APPLE_KEY_ID" --issuer "$APPLE_ISSUER_ID"
   ```

8. Run the next end-to-end publish while the old key remains active.
9. After the publish succeeds, revoke the old key in App Store Connect and delete its downloaded private key. Revocation cannot be undone.

If verification fails, restore all three old API values as a set.

## Create a replacement signing identity

Repeat this preparation for Apple Development, Apple Distribution, or Developer ID Application.

1. Open **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**.
2. Enter the Apple Developer account email, choose **Saved to disk**, and save the CSR. This also creates its private key in the login keychain.
3. Open **Certificates, Identifiers & Profiles → Certificates** in the Apple Developer portal.
4. Create the required certificate type for team `GRAHAM ALLAN OTTE (3QCHM255VF)` and upload the CSR.
5. Download and open the `.cer` file so Keychain Access joins it to the generated private key.
6. In **My Certificates**, expand the new certificate and confirm a private key appears below it.
7. Inspect the certificate and confirm its organization and organizational unit match the expected team.
8. Select only that identity, export it as `.p12`, and assign a new password.
9. Encode it:

   ```sh
   base64 -i certificate.p12
   ```

10. Update the matching `*_CERTIFICATE_BASE64` and `*_CERTIFICATE_PASSWORD` values together.

The publish workflow imports this identity into an isolated temporary keychain under `publish/tmp/apps` and passes it to signing with `--keychain`. Leaving the identity installed in the login keychain should not change which identity the workflow uses.

While signing, the temporary keychain is added to the front of the user's search list. The default keychain and the rest of the search list are left unchanged. The `keychain` gem snapshots those settings first and restores them when signing finishes, fails, or is interrupted. If the process is killed, `mise manager:trigger` restores the snapshot on its next run.

## Verify a replacement identity

Load `.env.production`, then run the command matching the rotated certificate. Each command only imports and validates the identity in the same temporary-keychain path used by publishing; it does not publish anything.

```sh
set -a
source .env.production
set +a
cd publish

bundle exec ruby -e 'require_relative "lib/require"; Apps.with_signing_certificate("Apple Development", "APPLE_DEVELOPMENT") { puts "Apple Development identity is valid" }'

bundle exec ruby -e 'require_relative "lib/require"; Apps.with_signing_certificate("Apple Distribution", "APPLE_DISTRIBUTION") { puts "Apple Distribution identity is valid" }'

bundle exec ruby -e 'require_relative "lib/require"; Apps.with_signing_certificates([["Mac Developer Installer", "APPLE_MAC_INSTALLER_DISTRIBUTION", nil]]) { puts "Mac Installer Distribution identity is valid" }'

bundle exec ruby -e 'require_relative "lib/require"; Apps.with_signing_certificate("Developer ID Application", "APPLE_DEVELOPER_ID") { puts "Developer ID identity is valid" }'
```

Return to the repository root and run `mise test`. Keep the previous certificate active until an end-to-end publish proves the relevant archive, export, upload, and, for Developer ID, notarization paths.

### Apple Development

Create an **Apple Development** certificate. Apple limits the number of active development certificates, so the portal may require an obsolete certificate to be revoked before a replacement can be created. Confirm ownership and authorization before doing that. Revoking a development certificate invalidates profiles that use it; the publish workflow recreates required profiles through Xcode and the API key.

### Apple Distribution

Create an **Apple Distribution** certificate. Revoking it invalidates profiles that use it, so retain the old certificate until the new one has successfully exported and uploaded every App Store target.

### Developer ID Application

Create a **Developer ID Application** certificate. Do not revoke an old Developer ID certificate as routine cleanup: revocation can prevent users from installing apps signed with it. Apple normally requires contacting Developer Program Support to revoke one. Allow an uncompromised old certificate to expire after the replacement is proven.

### Mac Installer Distribution

Create a **Mac Installer Distribution** certificate. Apple requires it in addition to Apple Distribution when Xcode packages a Mac App Store upload.

## Rollback and troubleshooting

- Restore both old certificate environment values if identity import, archive, or export fails.
- Restore all three old API-key values if authentication, provisioning, upload, or notarization fails.
- `Missing ... identity` usually means the wrong certificate type was exported or the `.p12` lacks its private key.
- An API `401` usually means the issuer ID, key ID, and `.p8` do not belong together.
- A provisioning failure after certificate revocation usually means a profile still references the revoked certificate. Remove only the identified stale profile from `~/Library/Developer/Xcode/UserData/Provisioning Profiles` and retry so Xcode can recreate it.
- Never broadly delete keychains, certificates, or provisioning profiles while troubleshooting.

## Apple references

- [App Store Connect API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
- [Create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)
- [Certificate types and purposes](https://developer.apple.com/help/account/create-certificates/certificates-overview)
- [Revoke a certificate](https://developer.apple.com/help/account/certificates/revoke-a-certificate)
- [Revoking privileges and Developer ID consequences](https://developer.apple.com/help/account/reference/revoking-privileges/)
