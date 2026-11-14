#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run after adding Swift files."""
from pathlib import Path
import hashlib
import json
import plistlib
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def project_data():
    objects = {}

    def add(key_name, isa, **fields):
        key = uid(key_name)
        objects[key] = dict(isa=isa, **fields)
        return key

    def file(group, name, kind):
        return add(f"file.{group}.{name}", "PBXFileReference", lastKnownFileType=kind, path=name, sourceTree="<group>")

    app_files = [file("app", p.name, "sourcecode.swift") for p in sorted((ROOT / "Folio").glob("*.swift"))]
    unit_files = [file("tests", p.name, "sourcecode.swift") for p in sorted((ROOT / "FolioTests").glob("*.swift"))]
    ui_files = [file("ui", p.name, "sourcecode.swift") for p in sorted((ROOT / "FolioUITests").glob("*.swift"))]
    assets = file("app", "Assets.xcassets", "folder.assetcatalog")
    info = file("app", "Info.plist", "text.plist.xml")
    privacy = file("app", "PrivacyInfo.xcprivacy", "text.plist.xml")
    fixtures = add("file.fixtures", "PBXFileReference", lastKnownFileType="folder", path="Tests/FolioCoreTests/Fixtures", sourceTree="SOURCE_ROOT")
    products = {}
    for name, ext, kind in [("app", "app", "wrapper.application"), ("tests", "xctest", "wrapper.cfbundle"), ("ui", "xctest", "wrapper.cfbundle")]:
        title = {"app": "Folio", "tests": "FolioTests", "ui": "FolioUITests"}[name]
        products[name] = add("product." + name, "PBXFileReference", explicitFileType=kind, includeInIndex=0, path=title + "." + ext, sourceTree="BUILT_PRODUCTS_DIR")
    product_group = add("group.products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
    groups = [
        add("group.app", "PBXGroup", children=app_files + [assets, info, privacy], path="Folio", sourceTree="<group>"),
        add("group.tests", "PBXGroup", children=unit_files, path="FolioTests", sourceTree="<group>"),
        add("group.ui", "PBXGroup", children=ui_files, path="FolioUITests", sourceTree="<group>"), fixtures, product_group,
    ]
    main = add("group.main", "PBXGroup", children=groups, sourceTree="<group>")
    package = add("package.core", "XCLocalSwiftPackageReference", relativePath=".")
    core_products = {kind: add("package.product." + kind, "XCSwiftPackageProductDependency", package=package, productName="FolioCore") for kind in ["app", "tests"]}

    def phase(kind, stage, refs, product=False):
        builds = [add(f"build.{kind}.{stage}.{ref}", "PBXBuildFile", **{("productRef" if product else "fileRef"): ref}) for ref in refs]
        return add(f"phase.{kind}.{stage}", {"sources": "PBXSourcesBuildPhase", "resources": "PBXResourcesBuildPhase", "frameworks": "PBXFrameworksBuildPhase"}[stage], buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)

    shared = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"}

    def configs(name, extra):
        values = []
        for config in ["Debug", "Release"]:
            settings = dict(shared, **extra)
            settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O", "SWIFT_COMPILATION_MODE": "singlefile" if config == "Debug" else "wholemodule", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if config == "Debug" else "$(inherited)", "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO", "ONLY_ACTIVE_ARCH": "YES" if config == "Debug" else "NO"})
            values.append(add(f"config.{name}.{config}", "XCBuildConfiguration", buildSettings=settings, name=config))
        return add("configs." + name, "XCConfigurationList", buildConfigurations=values, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    target_shared = {"CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "", "TARGETED_DEVICE_FAMILY": "2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "PRODUCT_NAME": "$(TARGET_NAME)", "MARKETING_VERSION": "3.0.0", "CURRENT_PROJECT_VERSION": "1", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"}
    targets = []
    for kind, sources, title in [("app", app_files, "Folio"), ("tests", unit_files, "FolioTests"), ("ui", ui_files, "FolioUITests")]:
        settings = dict(target_shared, PRODUCT_BUNDLE_IDENTIFIER="net.sahlab.folio" + ("" if kind == "app" else "." + title))
        if kind == "app":
            settings.update(INFOPLIST_FILE="Folio/Info.plist", GENERATE_INFOPLIST_FILE="NO", ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon")
        else:
            settings["GENERATE_INFOPLIST_FILE"] = "YES"
            if kind == "tests":
                settings.update(TEST_HOST="$(BUILT_PRODUCTS_DIR)/Folio.app/Folio", BUNDLE_LOADER="$(TEST_HOST)")
            else:
                settings["TEST_TARGET_NAME"] = "Folio"
        dependencies = []
        if kind != "app":
            proxy = add("proxy." + kind, "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1, remoteGlobalIDString=uid("target.app"), remoteInfo="Folio")
            dependencies = [add("dependency." + kind, "PBXTargetDependency", target=uid("target.app"), targetProxy=proxy)]
        frameworks = [core_products[kind]] if kind in core_products else []
        resources = [assets, privacy] if kind == "app" else [fixtures] if kind == "tests" else []
        targets.append(add("target." + kind, "PBXNativeTarget", buildConfigurationList=configs(kind, settings), buildPhases=[phase(kind, "sources", sources), phase(kind, "frameworks", frameworks, True), phase(kind, "resources", resources)], buildRules=[], dependencies=dependencies, name=title, packageProductDependencies=frameworks, productName=title, productReference=products[kind], productType="com.apple.product-type.application" if kind == "app" else "com.apple.product-type.bundle.unit-test" if kind == "tests" else "com.apple.product-type.bundle.ui-testing"))
    project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600", "TargetAttributes": {uid("target.app"): {"CreatedOnToolsVersion": "16.0"}, uid("target.tests"): {"CreatedOnToolsVersion": "16.0", "TestTargetID": uid("target.app")}, uid("target.ui"): {"CreatedOnToolsVersion": "16.0", "TestTargetID": uid("target.app")}}}, buildConfigurationList=configs("project", {}), compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main, packageReferences=[package], productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
    return dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)


def openstep(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join("\t" + pad + json.dumps(k) + " = " + openstep(v, indent + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" + pad + openstep(v, indent + 1) + ",\n" for v in value) + pad + ")"
    return str(value) if isinstance(value, int) else json.dumps(value, ensure_ascii=True)


def scheme():
    def buildable(kind, title, ext):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target." + kind)}" BuildableName="{title}.{ext}" BlueprintName="{title}" ReferencedContainer="container:Folio.xcodeproj"/>'
    app = buildable("app", "Folio", "app")
    testables = "".join(f'<TestableReference skipped="NO">{buildable(kind, title, "xctest")}</TestableReference>' for kind, title in [("tests", "FolioTests"), ("ui", "FolioUITests")])
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" codeCoverageEnabled="YES"><Testables>{testables}</Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''


def icon():
    size = 1024
    data = bytearray()
    for y in range(size):
        data.append(0)
        for x in range(size):
            color = (21, 32, 33)
            if 220 <= x <= 798 and 160 <= y <= 864:
                color = (173, 197, 161)
            if 250 <= x <= 275 and 160 <= y <= 864:
                color = (110, 140, 110)
            if (371 <= x <= 426 and 320 <= y <= 714) or (371 <= x <= 657 and 320 <= y <= 375) or (371 <= x <= 602 and 487 <= y <= 542):
                color = (30, 49, 43)
            data.extend(color)
    def chunk(tag, content):
        return struct.pack(">I", len(content)) + tag + content + struct.pack(">I", zlib.crc32(tag + content))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(data), 9)) + chunk(b"IEND", b"")


def write_project():
    project = ROOT / "Folio.xcodeproj"
    schemes = project / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + openstep(project_data()) + "\n")
    (schemes / "Folio.xcscheme").write_text(scheme())
    info = {"CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "Folio", "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "LSRequiresIPhoneOS": True, "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}, "UILaunchScreen": {}, "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"], "NSMicrophoneUsageDescription": "Record voice notes when you tap the microphone in a notebook.", "LSSupportsOpeningDocumentsInPlace": True, "CFBundleURLTypes": [{"CFBundleURLName": "net.sahlab.folio.links", "CFBundleURLSchemes": ["folio"]}], "CFBundleDocumentTypes": [{"CFBundleTypeName": "Folio Notebook", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Owner", "LSItemContentTypes": ["net.sahlab.folio.notebook"]}, {"CFBundleTypeName": "Documents", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate", "LSItemContentTypes": ["com.pkware.zip-archive", "com.adobe.pdf", "org.openxmlformats.wordprocessingml.document", "public.plain-text"]}], "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "net.sahlab.folio.notebook", "UTTypeDescription": "Folio editable notebook", "UTTypeConformsTo": ["com.pkware.zip-archive"], "UTTypeTagSpecification": {"public.filename-extension": ["folio"], "public.mime-type": "application/x-folio"}}]}
    (ROOT / "Folio/Info.plist").write_bytes(plistlib.dumps(info))
    privacy = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [], "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]}]}
    (ROOT / "Folio/PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(privacy))
    assets = ROOT / "Folio/Assets.xcassets"
    appicon = assets / "AppIcon.appiconset"
    appicon.mkdir(parents=True, exist_ok=True)
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (appicon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (appicon / "AppIcon.png").write_bytes(icon())


if __name__ == "__main__":
    write_project()
    print("Generated Folio.xcodeproj, shared scheme, app metadata, and icon.")
