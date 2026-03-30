# iOS CI/CD — GitHub Actions to TestFlight

## Workflow

Push to `ios/**` on `main` triggers `.github/workflows/ios-deploy.yml`:
1. Build the Xcode project on macOS runner
2. Sign with your distribution certificate
3. Export IPA
4. Upload to TestFlight via App Store Connect API

## Required GitHub Secrets

You need to set these in GitHub → Settings → Secrets → Actions:

### Signing

| Secret | How to get it |
|--------|---------------|
| `IOS_BUILD_CERTIFICATE_BASE64` | Export your Apple Distribution certificate as .p12 from Keychain Access, then `base64 -i cert.p12` |
| `IOS_P12_PASSWORD` | Password you set when exporting the .p12 |
| `IOS_PROVISION_PROFILE_BASE64` | Download App Store provisioning profile from Apple Developer portal, then `base64 -i profile.mobileprovision` |
| `IOS_KEYCHAIN_PASSWORD` | Any random string (used for temporary CI keychain) |
| `IOS_TEAM_ID` | Your Apple Developer Team ID (found in developer.apple.com → Membership) |

### App Store Connect API

| Secret | How to get it |
|--------|---------------|
| `IOS_API_KEY_ID` | Create API key at appstoreconnect.apple.com → Users and Access → Keys |
| `IOS_API_ISSUER_ID` | Shown on the same Keys page |
| `IOS_API_KEY_BASE64` | Download the .p8 key file, then `base64 -i AuthKey_XXX.p8` |

## Setup Steps

### 1. Apple Developer Account
- Enroll at developer.apple.com ($99/year)
- Create an App ID for `com.shantisangha.app` (or your bundle ID)

### 2. Certificate
- In Xcode: Settings → Accounts → Manage Certificates → + Apple Distribution
- Or via developer.apple.com → Certificates

### 3. Provisioning Profile
- developer.apple.com → Profiles → + App Store
- Select your App ID and Distribution certificate

### 4. App Store Connect
- Create app at appstoreconnect.apple.com
- Bundle ID must match your Xcode project
- Create API key with "App Manager" role

### 5. Encode secrets
```bash
# Certificate
base64 -i Certificates.p12 | pbcopy
# → paste as IOS_BUILD_CERTIFICATE_BASE64

# Provisioning profile
base64 -i ShantiSangha.mobileprovision | pbcopy
# → paste as IOS_PROVISION_PROFILE_BASE64

# API key
base64 -i AuthKey_XXXXXX.p8 | pbcopy
# → paste as IOS_API_KEY_BASE64
```

### 6. Add secrets to GitHub
GitHub → repo → Settings → Secrets and variables → Actions → New repository secret

## Manual Trigger

You can also trigger the workflow manually:
GitHub → Actions → iOS Deploy → Run workflow
