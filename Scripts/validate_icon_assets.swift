#!/usr/bin/env swift
import AppKit
import Foundation

struct ExpectedPNG {
    let path: String
    let width: Int
    let height: Int
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fileManager = FileManager.default

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func requireFile(_ relativePath: String) -> URL {
    let url = root.appendingPathComponent(relativePath)
    guard fileManager.fileExists(atPath: url.path) else {
        fail("Missing file: \(relativePath)")
    }
    return url
}

func dimensions(of url: URL) -> (Int, Int) {
    guard let image = NSImage(contentsOf: url),
          let representation = image.representations.first else {
        fail("Could not read PNG: \(url.path)")
    }
    return (representation.pixelsWide, representation.pixelsHigh)
}

func jsonObject(_ relativePath: String) -> [String: Any] {
    let url = requireFile(relativePath)
    do {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("JSON root is not an object: \(relativePath)")
        }
        return object
    } catch {
        fail("Could not parse JSON at \(relativePath): \(error)")
    }
}

struct ImageEntry: Hashable, CustomStringConvertible {
    let idiom: String
    let size: String?
    let scale: String
    let filename: String

    var description: String {
        if let size {
            return "{filename: \(filename), idiom: \(idiom), scale: \(scale), size: \(size)}"
        }
        return "{filename: \(filename), idiom: \(idiom), scale: \(scale)}"
    }
}

func imageEntry(_ image: [String: Any], index: Int, expectedKeys: Set<String>, catalogName: String) -> ImageEntry {
    let actualKeys = Set(image.keys)
    guard actualKeys == expectedKeys else {
        fail("\(catalogName) image entry \(index) keys mismatch. Expected \(expectedKeys.sorted()), got \(actualKeys.sorted())")
    }

    guard let idiom = image["idiom"] as? String else {
        fail("\(catalogName) image entry \(index) has invalid idiom")
    }
    guard let scale = image["scale"] as? String else {
        fail("\(catalogName) image entry \(index) has invalid scale")
    }
    guard let filename = image["filename"] as? String else {
        fail("\(catalogName) image entry \(index) has invalid filename")
    }

    let size: String?
    if expectedKeys.contains("size") {
        guard let sizeValue = image["size"] as? String else {
            fail("\(catalogName) image entry \(index) has invalid size")
        }
        size = sizeValue
    } else {
        size = nil
    }

    return ImageEntry(idiom: idiom, size: size, scale: scale, filename: filename)
}

func imageEntryListDescription(_ entries: Set<ImageEntry>) -> [String] {
    entries.map(\.description).sorted()
}

func integerValue(_ value: Any?) -> Int? {
    if value is Bool {
        return nil
    }
    if let value = value as? NSNumber {
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return nil
        }

        let integerTypes: Set<String> = ["c", "i", "s", "l", "q", "C", "I", "S", "L", "Q"]
        guard integerTypes.contains(String(cString: value.objCType)) else {
            return nil
        }
        return value.intValue
    }
    if let value = value as? Int {
        return value
    }
    return nil
}

func validateImageEntries(_ images: [[String: Any]], expected: Set<ImageEntry>, expectedKeys: Set<String>, catalogName: String) {
    guard images.count == expected.count else {
        fail("\(catalogName) image count mismatch. Expected \(expected.count), got \(images.count)")
    }

    let actual = images.enumerated().map { index, image in
        imageEntry(image, index: index, expectedKeys: expectedKeys, catalogName: catalogName)
    }

    let actualSet = Set(actual)
    guard actualSet.count == actual.count else {
        fail("\(catalogName) image entries contain duplicates")
    }

    guard actualSet == expected else {
        fail("\(catalogName) image entries mismatch. Expected \(imageEntryListDescription(expected)), got \(imageEntryListDescription(actualSet))")
    }
}

func validateInfo(_ json: [String: Any], catalogName: String) {
    guard let info = json["info"] as? [String: Any] else {
        fail("\(catalogName) Contents.json has no info object")
    }
    guard Set(info.keys) == ["author", "version"] else {
        fail("\(catalogName) Contents.json info keys mismatch. Expected [\"author\", \"version\"], got \(info.keys.sorted())")
    }
    guard info["author"] as? String == "xcode" else {
        fail("\(catalogName) Contents.json info.author must be xcode")
    }
    guard integerValue(info["version"]) == 1 else {
        fail("\(catalogName) Contents.json info.version must be 1")
    }
}

let expectedPNGs = [
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-16x16@1x.png", width: 16, height: 16),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-16x16@2x.png", width: 32, height: 32),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-32x32@1x.png", width: 32, height: 32),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-32x32@2x.png", width: 64, height: 64),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-128x128@1x.png", width: 128, height: 128),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-128x128@2x.png", width: 256, height: 256),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-256x256@1x.png", width: 256, height: 256),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-256x256@2x.png", width: 512, height: 512),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-512x512@1x.png", width: 512, height: 512),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/AppIcon.appiconset/AppIcon-512x512@2x.png", width: 1024, height: 1024),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon.png", width: 18, height: 18),
    ExpectedPNG(path: "MenuBarMemo/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon@2x.png", width: 36, height: 36)
]

for expected in expectedPNGs {
    let url = requireFile(expected.path)
    let actual = dimensions(of: url)
    guard actual.0 == expected.width && actual.1 == expected.height else {
        fail("Wrong dimensions for \(expected.path): expected \(expected.width)x\(expected.height), got \(actual.0)x\(actual.1)")
    }
}

let appIconJSON = jsonObject("MenuBarMemo/Assets.xcassets/AppIcon.appiconset/Contents.json")
guard let appImages = appIconJSON["images"] as? [[String: Any]] else {
    fail("AppIcon Contents.json has no images array")
}
validateInfo(appIconJSON, catalogName: "AppIcon")
validateImageEntries(appImages, expected: [
    ImageEntry(idiom: "mac", size: "16x16", scale: "1x", filename: "AppIcon-16x16@1x.png"),
    ImageEntry(idiom: "mac", size: "16x16", scale: "2x", filename: "AppIcon-16x16@2x.png"),
    ImageEntry(idiom: "mac", size: "32x32", scale: "1x", filename: "AppIcon-32x32@1x.png"),
    ImageEntry(idiom: "mac", size: "32x32", scale: "2x", filename: "AppIcon-32x32@2x.png"),
    ImageEntry(idiom: "mac", size: "128x128", scale: "1x", filename: "AppIcon-128x128@1x.png"),
    ImageEntry(idiom: "mac", size: "128x128", scale: "2x", filename: "AppIcon-128x128@2x.png"),
    ImageEntry(idiom: "mac", size: "256x256", scale: "1x", filename: "AppIcon-256x256@1x.png"),
    ImageEntry(idiom: "mac", size: "256x256", scale: "2x", filename: "AppIcon-256x256@2x.png"),
    ImageEntry(idiom: "mac", size: "512x512", scale: "1x", filename: "AppIcon-512x512@1x.png"),
    ImageEntry(idiom: "mac", size: "512x512", scale: "2x", filename: "AppIcon-512x512@2x.png")
], expectedKeys: ["idiom", "size", "scale", "filename"], catalogName: "AppIcon")

let statusJSON = jsonObject("MenuBarMemo/Assets.xcassets/StatusBarIcon.imageset/Contents.json")
guard let statusImages = statusJSON["images"] as? [[String: Any]] else {
    fail("StatusBarIcon Contents.json has no images array")
}
validateInfo(statusJSON, catalogName: "StatusBarIcon")
validateImageEntries(statusImages, expected: [
    ImageEntry(idiom: "mac", size: nil, scale: "1x", filename: "StatusBarIcon.png"),
    ImageEntry(idiom: "mac", size: nil, scale: "2x", filename: "StatusBarIcon@2x.png")
], expectedKeys: ["idiom", "scale", "filename"], catalogName: "StatusBarIcon")
let properties = statusJSON["properties"] as? [String: Any]
guard properties?["template-rendering-intent"] as? String == "template" else {
    fail("StatusBarIcon.imageset must set template-rendering-intent to template")
}

_ = requireFile("MenuBarMemo/IconSource/MenuBarMemoAppIcon.svg")
_ = requireFile("MenuBarMemo/IconSource/MenuBarMemoStatusBarIcon.svg")

print("Icon asset validation passed")
