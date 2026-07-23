import Foundation
import ObjectiveC.runtime

// TwitterDash is a private Swift module, so the tweak cannot import its item
// structs at build time. Mirror preserves each concrete runtime type inside
// Any, which lets this helper reorder the existing arrays without fabricating
// private values or touching their action closures.
@objc(BHTSidebarRuntime)
public final class BHTSidebarRuntime: NSObject {
    private static let visibleItemsKey = "bht_sidebar_navigation_visible"
    private static let canonicalIDs = [
        "profile",
        "blue",
        "history",
        "communities",
        "news",
        "lists",
        "chat",
        "notifications",
        "spaces",
        "follow_requests",
    ]

    @objc(applyToDataSource:)
    public static func apply(to dataSource: AnyObject) {
        let visible = UserDefaults.standard.stringArray(forKey: visibleItemsKey)
            ?? canonicalIDs
        let rank = Dictionary(
            uniqueKeysWithValues: visible.enumerated().map { ($1, $0) }
        )
        let selected = Set(visible)

        for child in Mirror(reflecting: dataSource).children {
            guard let label = child.label,
                  label == "primaryItems"
                    || label == "folderItems"
                    || label == "tertiaryItems"
            else {
                continue
            }
            rewriteArray(
                child.value,
                on: dataSource,
                selected: selected,
                rank: rank
            )
        }
    }

    private static func rewriteArray(
        _ value: Any,
        on dataSource: AnyObject,
        selected: Set<String>,
        rank: [String: Int]
    ) {
        func open<T>(_ concreteValue: T) {
            rewriteConcreteArray(
                concreteValue,
                on: dataSource,
                selected: selected,
                rank: rank
            )
        }
        _openExistential(value, do: open)
    }

    private static func rewriteConcreteArray<T>(
        _ original: T,
        on dataSource: AnyObject,
        selected: Set<String>,
        rank: [String: Int]
    ) {
        guard MemoryLayout<T>.size == MemoryLayout<UInt>.size,
              let values = original as? [Any]
        else {
            return
        }

        let recognized = values.compactMap { value -> (String, Any)? in
            guard let identifier = identifier(for: value) else {
                return nil
            }
            return (identifier, value)
        }
        guard !recognized.isEmpty else {
            return
        }

        let ordered = recognized
            .filter { selected.contains($0.0) }
            .sorted {
                let left = rank[$0.0] ?? Int.max
                let right = rank[$1.0] ?? Int.max
                return left < right
            }
            .map { $0.1 }

        // Leave X-owned rows (Settings, Monetization, account switching, and
        // future additions) in their original relative order. The configured
        // rows replace the first matching block in the requested order.
        var replacement: [Any] = []
        var insertedConfiguredItems = false
        for value in values {
            if identifier(for: value) != nil {
                if !insertedConfiguredItems {
                    replacement.append(contentsOf: ordered)
                    insertedConfiguredItems = true
                }
            } else {
                replacement.append(value)
            }
        }

        guard let typedReplacement = replacement as? T else {
            return
        }
        store(
            typedReplacement,
            replacing: original,
            in: dataSource
        )
    }

    private static func store<T>(
        _ replacement: T,
        replacing original: T,
        in object: AnyObject
    ) {
        let originalWord = withUnsafeBytes(of: original) {
            $0.load(as: UInt.self)
        }
        guard originalWord != 0,
              let objectClass = object_getClass(object)
        else {
            return
        }

        let base = Unmanaged.passUnretained(object).toOpaque()
        let instanceSize = class_getInstanceSize(objectClass)
        let wordSize = MemoryLayout<UInt>.size
        guard instanceSize >= wordSize * 2 else {
            return
        }

        for offset in stride(
            from: wordSize,
            to: instanceSize - wordSize + 1,
            by: wordSize
        ) {
            let candidate = base.load(
                fromByteOffset: offset,
                as: UInt.self
            )
            if candidate == originalWord {
                base.advanced(by: offset)
                    .assumingMemoryBound(to: T.self)
                    .pointee = replacement
                return
            }
        }
    }

    private static func identifier(for value: Any) -> String? {
        guard let title = Mirror(reflecting: value).children
            .first(where: { $0.label == "title" })?
            .value as? String
        else {
            return nil
        }
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "profile":
            return "profile"
        case "blue", "premium", "get verified", "twitter blue":
            return "blue"
        case "history":
            return "history"
        case "communities":
            return "communities"
        case "news":
            return "news"
        case "lists":
            return "lists"
        case "chat", "messages", "direct messages":
            return "chat"
        case "notifications":
            return "notifications"
        case "spaces":
            return "spaces"
        case "follow requests", "follower requests":
            return "follow_requests"
        default:
            return nil
        }
    }
}
