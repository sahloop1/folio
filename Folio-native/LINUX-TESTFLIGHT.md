# Install native Folio from Linux using a cloud Mac and TestFlight

Prepared on 2026-11-14. This setup has not been executed against a connected Apple or Codemagic account. Folio still needs its first successful Xcode build. Paying for Apple membership does not finish the port or establish that it runs on an iPad.

The intended result is a signed native app installed by Apple's TestFlight, with its own Home Screen icon and local notebook storage. Codemagic is the hosted Mac that compiles/signs the app; you manage its account from Linux. Apple membership is USD 99 per year or the applicable local price. Codemagic currently includes 500 monthly macOS M2 minutes for personal accounts; additional usage or other plans can cost more.

TestFlight builds expire 90 days after upload. Upload and install an updated build before expiry to keep using a beta. An App Store release, after the app is working and Apple has reviewed it, avoids the TestFlight build-expiration cycle. Do not delete Folio to update it; keep Files backups of your notes.

## 1. Create the build-service accounts and upload the source

You can complete this and the unsigned build before paying Apple.

1. Create/sign in to your GitHub account at https://github.com/.
2. Create a **private** repository named `folio-ipad`. Initialize it with a README so the upload screen is available.
3. Extract the latest `dist/Folio-iPad-Native-3.0.0-source.zip` from this workspace.
4. On GitHub, open the repository → **Add file → Upload files**. Drag the extracted **Folio-native folder** and **codemagic.yaml file** into the upload area, then commit. Upload the extracted contents, not the ZIP. The root of the repository must contain `codemagic.yaml` and `Folio-native/Folio.xcodeproj/project.pbxproj`. Do not upload the Android checkout, real notebooks, or signing files.
5. Sign up at https://codemagic.io/ using your GitHub account. Use a **personal account** for its current free M2 allowance, rather than creating a paid team.
6. Choose **Add application**, connect only the repository you created, select it, and use its `codemagic.yaml` configuration.
7. Start **Folio - compile and test first**. It needs no Apple signing setup. If it fails, open/download the failed build log and bring the compiler or test error back to this project so it can be fixed. This workflow does not produce an installable app.

If working from the original workspace rather than the source ZIP, the root YAML uses `ipad-native/` instead of `Folio-native/`. The source packager adjusts it automatically; do not mix files from the two layouts.

## 2. Enroll with Apple

1. On iPad, sign in to iCloud with an Apple Account that has two-factor authentication enabled.
2. Install Apple's **Apple Developer** app from the App Store.
3. Open **Account**, sign in, then choose **Enroll Now**. Use **Individual** and your legal information; complete identity verification if requested.
4. When Apple offers the purchase, review the annual price and subscribe. Wait for membership activation; an enrollment request or payment receipt alone may not mean it is active.
5. If app enrollment is unavailable in your region, use https://developer.apple.com/programs/enroll/.
6. Install Apple's **TestFlight** app on the iPad as well.

The fee is annual, not a one-time app purchase. Enrollment and payment happen directly with Apple.

## 3. Register Folio in your Apple account

On Linux, use your browser:

1. Open https://developer.apple.com/account/ → **Certificates, Identifiers & Profiles → Identifiers → +**.
2. Choose **App IDs → App**, description **Folio**, and an **Explicit** bundle ID of `net.sahlab.folio`. Leave additional capabilities off; this native source does not require iCloud, push, or in-app purchases. Register it.
3. If that bundle ID is unavailable, stop at this step and choose a unique replacement together with the source configuration. The app, provisioning profile, and YAML must all match; changing only the Apple website will not work.
4. Open https://appstoreconnect.apple.com/. Accept any pending developer agreements Apple requires.
5. Choose **Apps → + → New App**. Select **iOS** (which includes iPadOS), a name such as **Folio Personal Notes**, your primary language, the registered bundle ID, and SKU `folio-ipad-001`. Use a different app name if Apple says it is unavailable. Create the record. This does not publicly release it.

## 4. Connect Apple's API to Codemagic

1. In App Store Connect, open **Users and Access → Integrations → App Store Connect API → Team Keys**. Request API access if Apple shows that prerequisite; wait for approval if necessary.
2. Generate a **team** API key named **Folio cloud build** with **App Manager** access. An individual API key cannot use Apple's provisioning endpoints.
3. Download the `.p8` file once and retain the **Key ID** and **Issuer ID** displayed by Apple.
4. In your Codemagic personal-account settings, find the **Developer Portal** integration and add the key. Set the integration's key name to exactly **Folio**, matching `integrations.app_store_connect` in the YAML. Enter the Issuer ID and Key ID and upload the `.p8` there.

Keep the `.p8` out of GitHub and chat. It belongs in the build service's private signing integration, not in the app source.

## 5. Add distribution signing resources

1. In Codemagic settings → **Code signing identities → iOS certificates**, use **Generate certificate** with type **Apple Distribution** and the **Folio** Apple integration. Give it a reference name such as `FolioDistribution`.
2. Save the generated `.p12` and its password, then upload/add that certificate to the same account's iOS signing identities if the UI requires that separate step. Both the certificate and its private key must be available to the builder.
3. Back in Apple's **Certificates, Identifiers & Profiles → Profiles → +**, choose the **App Store Connect** distribution profile for iOS/iPadOS (older screens may label it **App Store**).
4. Select the `net.sahlab.folio` App ID and the distribution certificate just generated. Name the profile **Folio App Store**, generate it, and download it.
5. In Codemagic **Code signing identities → iOS provisioning profiles**, upload that `.mobileprovision` file with reference name `FolioAppStore`, or fetch/select the profile using the Apple integration.

The workflow selects those resources by `app_store` distribution type and `net.sahlab.folio` bundle ID. No iPad UDID registration is required for the TestFlight route.

## 6. Build, sign, and upload

1. In Codemagic, open the Folio application and start **Folio - signed build for private TestFlight** from the branch containing the source.
2. The workflow first reruns the native tests. Only after they pass does it set an increasing Apple build number, apply the configured profile, build/export a signed IPA, and upload it to your App Store Connect app record.
3. If compilation, tests, signing, or upload fail, the app is not ready to install. Use the failed step's log to resolve the error. There is no successful cloud build in this checkout yet.
4. Keep the same Codemagic application for later builds so its build counter keeps increasing. Switching services or recreating it may require setting a higher build-number baseline.

The publishing configuration uploads privately. It does not submit the app for public App Store review or external beta review, and it does not automatically assign testers.

## 7. Install on the iPad

1. In App Store Connect → your app → **TestFlight**, wait for Apple to process the build. Complete any export-compliance or other required build information shown by Apple.
2. Under **Internal Testing**, create a group such as **My iPad**. Add your own eligible App Store Connect user as a tester and add the processed build to that group.
3. Open the invitation on iPad, accept it in **TestFlight**, and tap **Install** next to Folio. You can then open Folio using its Home Screen icon.
4. First test a fresh notebook: handwriting, typing, relaunch, PDF export, and an audible voice recording. Then import a copy of the Android Folio library. Keep the Android originals until the real iPad checks pass.

## Official references

- Apple enrollment: https://developer.apple.com/help/account/membership/enrolling-in-the-app/
- Membership pricing: https://developer.apple.com/programs/enroll/
- App ID registration: https://developer.apple.com/help/account/identifiers/register-an-app-id/
- App Store Connect app record: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Team API keys: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/
- Distribution profile: https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/
- Internal TestFlight installation: https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/
- TestFlight expiry: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Codemagic signing: https://docs.codemagic.io/yaml-code-signing/signing-ios/
- Codemagic publishing: https://docs.codemagic.io/yaml-publishing/app-store-connect/
- Codemagic personal pricing: https://docs.codemagic.io/billing/pricing/
