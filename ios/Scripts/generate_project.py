"""Regenerate the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "pt.TetrisDuel"
objects = {}


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(object_name, isa, **values):
    key = identifier(object_name)
    objects[key] = dict(isa=isa, **values)
    return key


def serialize(value, indent=0):
    prefix = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(prefix + "\t" + json.dumps(str(k)) + " = " + serialize(v, indent+1) + ";\n"
                                  for k, v in value.items()) + prefix + "}"
    if isinstance(value, list):
        return "(\n" + "".join(prefix + "\t" + serialize(v, indent+1) + ",\n" for v in value) + prefix + ")"
    return json.dumps(str(value))


def group(name, directory, files):
    refs = []
    root = Path(directory)
    folders = {root: refs}
    for path in sorted(files):
        file_path = Path(path)
        parent = root
        children = refs
        for component in file_path.relative_to(root).parts[:-1]:
            parent = parent / component
            if parent not in folders:
                folders[parent] = []
                children.append(add(
                    "group:"+parent.as_posix(),
                    "PBXGroup",
                    path=component,
                    children=folders[parent],
                    sourceTree="<group>",
                ))

            children = folders[parent]

        file_type = {
            ".swift": "sourcecode.swift",
            ".xcassets": "folder.assetcatalog",
            ".plist": "text.plist.xml",
            ".xcprivacy": "text.xml",
            ".xcstrings": "text.json.xcstrings",
        }[file_path.suffix]
        children.append(add(
            "file:"+path,
            "PBXFileReference",
            lastKnownFileType=file_type,
            name=file_path.name,
            path=path,
            sourceTree="SOURCE_ROOT",
        ))

    result = add(
        "group:"+name,
        "PBXGroup",
        name=name,
        path=directory,
        children=refs,
        sourceTree="<group>",
    )
    return result


def phase(name, kind, paths):
    builds = [add("build:"+name+":"+p, "PBXBuildFile", fileRef=identifier("file:"+p)) for p in paths]
    return add("phase:"+name, kind, buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)


def configuration_list(name, settings):
    configs = []
    for mode in ("Debug", "Release"):
        values = dict(settings)
        values["ONLY_ACTIVE_ARCH"] = "YES" if mode == "Debug" else "NO"
        values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if mode == "Debug" else "-O"
        values["DEBUG_INFORMATION_FORMAT"] = "dwarf" if mode == "Debug" else "dwarf-with-dsym"
        if mode == "Debug":
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
            values["ENABLE_TESTABILITY"] = "YES"
        configs.append(add("config:"+name+mode, "XCBuildConfiguration", buildSettings=values, name=mode))
    return add("configlist:"+name, "XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def build():
    app_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "TetrisDuel").rglob("*.swift"))
    test_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "TetrisDuelTests").rglob("*.swift"))
    ui_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "TetrisDuelUITests").rglob("*.swift"))
    resources = [
        "TetrisDuel/Resources/Assets.xcassets",
        "TetrisDuel/Resources/PrivacyInfo.xcprivacy",
        "TetrisDuel/Resources/Localizable.xcstrings",
        "TetrisDuel/Resources/InfoPlist.xcstrings",
    ]
    groups = [
        group(
            "Application",
            "TetrisDuel",
            app_sources + resources + ["TetrisDuel/Resources/Info.plist"],
        ),
        group(
            "Unit Tests",
            "TetrisDuelTests",
            test_sources,
        ),
        group(
            "UI Tests",
            "TetrisDuelUITests",
            ui_sources,
        ),
    ]
    products = []
    targets = []
    common = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0",
              "SWIFT_STRICT_CONCURRENCY": "minimal", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
              "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
              "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
              "SWIFT_EMIT_LOC_STRINGS": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES"}
    for name, source, product_type in (
        (PROJECT_NAME, app_sources, "com.apple.product-type.application"),
        ("TetrisDuelTests", test_sources, "com.apple.product-type.bundle.unit-test"),
        ("TetrisDuelUITests", ui_sources, "com.apple.product-type.bundle.ui-testing"),
    ):
        is_app = name == PROJECT_NAME
        product = add("product:"+name, "PBXFileReference", explicitFileType="wrapper.application" if is_app else "wrapper.cfbundle",
                      includeInIndex=0, path=name+(".app" if is_app else ".xctest"), sourceTree="BUILT_PRODUCTS_DIR")
        products.append(product)
        phases = [phase(name+"Sources", "PBXSourcesBuildPhase", source), phase(name+"Frameworks", "PBXFrameworksBuildPhase", [])]
        phases.append(phase(name+"Resources", "PBXResourcesBuildPhase", resources if is_app else []))
        bundle_name = "TetrisDuel" if is_app else name
        settings = dict(
            common,
            PRODUCT_BUNDLE_IDENTIFIER="com.example."+bundle_name,
            PRODUCT_NAME="$(TARGET_NAME)",
        )
        if is_app:
            settings.update(
                INFOPLIST_FILE="TetrisDuel/Resources/Info.plist",
                GENERATE_INFOPLIST_FILE="NO",
                PRODUCT_MODULE_NAME=PROJECT_NAME.replace(".", "_"),
                ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
                LD_RUNPATH_SEARCH_PATHS=[
                    "$(inherited)", "@executable_path/Frameworks"
                ],
            )
        else:
            settings.update(GENERATE_INFOPLIST_FILE="YES")
            if name == "TetrisDuelTests":
                test_host = (
                    f"$(BUILT_PRODUCTS_DIR)/{PROJECT_NAME}.app/{PROJECT_NAME}"
                )
                settings.update(
                    TEST_HOST=test_host,
                    BUNDLE_LOADER="$(TEST_HOST)",
                    LD_RUNPATH_SEARCH_PATHS=[
                        "$(inherited)",
                        "@executable_path/Frameworks",
                        "@loader_path/Frameworks",
                    ],
                )
            else:
                settings.update(TEST_TARGET_NAME=PROJECT_NAME)

        dependencies = []
        if not is_app:
            proxy = add(
                "proxy:"+name,
                "PBXContainerItemProxy",
                containerPortal=identifier("project"),
                proxyType=1,
                remoteGlobalIDString=identifier("target:"+PROJECT_NAME),
                remoteInfo=PROJECT_NAME,
            )
            dependencies.append(add(
                "dependency:"+name,
                "PBXTargetDependency",
                target=identifier("target:"+PROJECT_NAME),
                targetProxy=proxy,
            ))

        targets.append(add("target:"+name, "PBXNativeTarget", buildConfigurationList=configuration_list(name, settings),
                           buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name,
                           productReference=product, productType=product_type))
    product_group = add("group:Products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
    main = add("group:Main", "PBXGroup", children=groups+[product_group], sourceTree="<group>")
    project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES",
                   "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0"} for target in targets}},
                  buildConfigurationList=configuration_list("Project", common), compatibilityVersion="Xcode 14.0",
                  developmentRegion="en",
                  hasScannedForEncodings=0,
                  knownRegions=["en", "ru", "Base"],
                  mainGroup=main,
                  productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
    output = ROOT / f"{PROJECT_NAME}.xcodeproj"
    output.mkdir(exist_ok=True)
    project_data = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
    (output / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(project_data) + "\n", encoding="utf-8")
    scheme(output)
    print(f"Generated {output.name}: {len(app_sources)} app, {len(test_sources)} unit-test, {len(ui_sources)} UI-test sources")


def scheme(output):
    def reference(parent, name):
        ET.SubElement(
            parent,
            "BuildableReference",
            BuildableIdentifier="primary",
            BlueprintIdentifier=identifier("target:"+name),
            BuildableName=name+(
                ".app" if name == PROJECT_NAME else ".xctest"
            ),
            BlueprintName=name,
            ReferencedContainer=f"container:{PROJECT_NAME}.xcodeproj",
        )

    root = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build_action = ET.SubElement(root, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build_action, "BuildActionEntries")
    for name in (PROJECT_NAME, "TetrisDuelTests", "TetrisDuelUITests"):
        app = name == PROJECT_NAME
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if app else "NO",
                              buildForProfiling="YES" if app else "NO", buildForArchiving="YES" if app else "NO", buildForAnalyzing="YES")
        reference(entry, name)
    test = ET.SubElement(root, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                         selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(test, "Testables")
    for name in ("TetrisDuelTests", "TetrisDuelUITests"):
        reference(ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), name)
    launch = ET.SubElement(root, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                          selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                          ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
    reference(
        ET.SubElement(
            launch,
            "BuildableProductRunnable",
            runnableDebuggingMode="0",
        ),
        PROJECT_NAME,
    )
    profile = ET.SubElement(root, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                           savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(
        ET.SubElement(
            profile,
            "BuildableProductRunnable",
            runnableDebuggingMode="0",
        ),
        PROJECT_NAME,
    )
    ET.SubElement(root, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(root, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(root)
    destination = (
        output / "xcshareddata" / "xcschemes" / f"{PROJECT_NAME}.xcscheme"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(destination, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    build()
