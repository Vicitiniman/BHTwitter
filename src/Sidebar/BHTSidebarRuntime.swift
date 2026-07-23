import Foundation
import Darwin

@_silgen_name("BHTInvokeTwitterDashArraySetter")
private func BHTInvokeTwitterDashArraySetter(
    _ arrayWord: UInt,
    _ object: UnsafeMutableRawPointer,
    _ setter: UnsafeMutableRawPointer
)

private final class BHTSidebarPropertyCache {
    var managedItems: [String: Any] = [:]
    var insertionIndex: Int?
}

private final class BHTSidebarDataSourceCache {
    weak var dataSource: AnyObject?
    var properties: [String: BHTSidebarPropertyCache] = [:]
    var isApplyingConfiguration = false

    init(dataSource: AnyObject) {
        self.dataSource = dataSource
    }
}

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
    private static let cacheLock = NSLock()
    private static var originalItemsCache:
        [ObjectIdentifier: BHTSidebarDataSourceCache] = [:]

    @objc(applyToDataSource:)
    public static func apply(to dataSource: AnyObject) {
        _ = applyConfiguration(to: dataSource)
    }

    // T1DashContentController is an Objective-C-visible Swift class, but its
    // private TwitterDash.DashDataSource property is not KVC-compliant in X
    // 12.9. Resolve the retained Swift object through reflection instead of
    // assuming valueForKey:@"dataSource" can cross that boundary.
    @objc(applyToDashContentController:)
    public static func apply(
        toDashContentController controller: AnyObject
    ) -> Bool {
        guard let dataSource = findDataSource(in: controller) else {
            return false
        }
        return applyConfiguration(to: dataSource)
    }

    @discardableResult
    private static func applyConfiguration(
        to dataSource: AnyObject
    ) -> Bool {
        guard beginConfiguration(on: dataSource) else {
            return false
        }
        defer { endConfiguration(on: dataSource) }

        let visible = UserDefaults.standard.stringArray(forKey: visibleItemsKey)
            ?? canonicalIDs
        let rank = Dictionary(
            uniqueKeysWithValues: visible.enumerated().map { ($1, $0) }
        )
        let selected = Set(visible)
        var changed = false

        var mirror: Mirror? = Mirror(reflecting: dataSource)
        while let current = mirror {
            for child in current.children {
                guard let label = child.label,
                      let property = sidebarPropertyName(from: label),
                      let array = reflectedArray(in: child.value)
                else {
                    continue
                }
                changed = rewriteArray(
                    array,
                    property: property,
                    on: dataSource,
                    selected: selected,
                    rank: rank
                ) || changed
            }
            mirror = current.superclassMirror
        }
        return changed
    }

    private static func sidebarPropertyName(
        from reflectedLabel: String
    ) -> String? {
        // @Published properties appear in Mirror as `_primaryItems` (the
        // Published wrapper), not as the public computed-property name.
        if reflectedLabel.hasSuffix("primaryItems") {
            return "primaryItems"
        }
        if reflectedLabel.hasSuffix("folderItems") {
            return "folderItems"
        }
        if reflectedLabel.hasSuffix("tertiaryItems") {
            return "tertiaryItems"
        }
        return nil
    }

    private static func reflectedArray(
        in value: Any,
        depth: Int = 0
    ) -> Any? {
        guard depth <= 4 else {
            return nil
        }
        if String(reflecting: type(of: value)).hasPrefix("Swift.Array<") {
            return value
        }

        // Unwrap Combine.Published<Array<...>> without naming its private
        // storage enum. This preserves the concrete private element type.
        for child in Mirror(reflecting: value).children {
            if let array = reflectedArray(
                in: child.value,
                depth: depth + 1
            ) {
                return array
            }
        }
        return nil
    }

    private static func findDataSource(
        in controller: AnyObject
    ) -> AnyObject? {
        var mirror: Mirror? = Mirror(reflecting: controller)
        while let current = mirror {
            for child in current.children {
                let value = unwrapOptional(child.value)
                let typeName = String(reflecting: type(of: value))
                if typeName.contains("TwitterDash.DashDataSource") {
                    return value as AnyObject
                }

                // Keep a label fallback for builds that strip the private
                // module name from reflected type metadata.
                if child.label?.hasSuffix("dataSource") == true,
                   Mirror(reflecting: value).displayStyle == .class {
                    return value as AnyObject
                }
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func unwrapOptional(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional,
              let wrapped = mirror.children.first?.value
        else {
            return value
        }
        return unwrapOptional(wrapped)
    }

    private static func rewriteArray(
        _ value: Any,
        property: String,
        on dataSource: AnyObject,
        selected: Set<String>,
        rank: [String: Int]
    ) -> Bool {
        func open<T>(_ concreteValue: T) -> Bool {
            return rewriteConcreteArray(
                concreteValue,
                property: property,
                on: dataSource,
                selected: selected,
                rank: rank
            )
        }
        return _openExistential(value, do: open)
    }

    private static func rewriteConcreteArray<T>(
        _ original: T,
        property: String,
        on dataSource: AnyObject,
        selected: Set<String>,
        rank: [String: Int]
    ) -> Bool {
        guard MemoryLayout<T>.size == MemoryLayout<UInt>.size,
              let values = original as? [Any]
        else {
            return false
        }

        let recognized = values.enumerated().compactMap {
            index, value -> (Int, String, Any)? in
            guard let identifier = identifier(for: value) else {
                return nil
            }
            return (index, identifier, value)
        }

        let cached = cachedManagedItems(
            property: property,
            on: dataSource,
            current: recognized
        )
        guard !cached.items.isEmpty else {
            return false
        }

        // Prefer the current native values for visible rows so live badges and
        // counts are not replaced by an older cached struct. The cache only
        // supplies rows that this tweak previously hid.
        var available = cached.items
        for (_, identifier, value) in recognized {
            available[identifier] = value
        }
        let ordered = available
            .filter { selected.contains($0.key) }
            .sorted {
                let left = rank[$0.key] ?? Int.max
                let right = rank[$1.key] ?? Int.max
                return left < right
            }
            .map { ($0.key, $0.value) }

        // The Published setter synchronously notifies SwiftUI. Avoid invoking
        // it when the managed sequence is already correct, otherwise a drawer
        // rebuild can recursively schedule another identical rebuild.
        let currentIDs = recognized.map { $0.1 }
        let desiredIDs = ordered.map { $0.0 }
        guard currentIDs != desiredIDs else {
            return false
        }

        // Leave X-owned rows (Settings, Monetization, account switching, and
        // future additions) in their exact relative order. The configured rows
        // replace the first matching block. If every managed row was hidden,
        // their original insertion point is recovered from the cache.
        var replacement: [Any] = []
        var insertedConfiguredItems = false
        let liveInsertionIndex = recognized.first?.0
        let insertionIndex = min(
            liveInsertionIndex ?? cached.insertionIndex,
            values.count
        )
        for (index, value) in values.enumerated() {
            if index == insertionIndex && !insertedConfiguredItems {
                replacement.append(contentsOf: ordered.map { $0.1 })
                insertedConfiguredItems = true
            }
            if identifier(for: value) != nil {
                continue
            } else {
                replacement.append(value)
            }
        }
        if !insertedConfiguredItems {
            replacement.append(contentsOf: ordered.map { $0.1 })
        }

        guard let typedReplacement = replacement as? T else {
            return false
        }

        // Use TwitterDash's real Swift setter when it is exported. Besides
        // avoiding assumptions about Swift-object ivar offsets, this emits the
        // observation change that its SwiftUI drawer needs to rebuild.
        return callSetter(
            for: property,
            replacement: typedReplacement,
            on: dataSource
        )
    }

    private static func cachedManagedItems(
        property: String,
        on dataSource: AnyObject,
        current: [(Int, String, Any)]
    ) -> (items: [String: Any], insertionIndex: Int) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        originalItemsCache = originalItemsCache.filter {
            $0.value.dataSource != nil
        }

        let dataSourceCache = cacheLocked(for: dataSource)

        let propertyCache: BHTSidebarPropertyCache
        if let existing = dataSourceCache.properties[property] {
            propertyCache = existing
        } else {
            let created = BHTSidebarPropertyCache()
            dataSourceCache.properties[property] = created
            propertyCache = created
        }

        if propertyCache.insertionIndex == nil,
           let firstIndex = current.first?.0 {
            propertyCache.insertionIndex = firstIndex
        }
        for (_, identifier, value) in current
            where propertyCache.managedItems[identifier] == nil {
            propertyCache.managedItems[identifier] = value
        }

        return (
            propertyCache.managedItems,
            propertyCache.insertionIndex ?? 0
        )
    }

    private static func beginConfiguration(
        on dataSource: AnyObject
    ) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        originalItemsCache = originalItemsCache.filter {
            $0.value.dataSource != nil
        }
        let cache = cacheLocked(for: dataSource)
        guard !cache.isApplyingConfiguration else {
            return false
        }
        cache.isApplyingConfiguration = true
        return true
    }

    private static func endConfiguration(on dataSource: AnyObject) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let key = ObjectIdentifier(dataSource)
        guard let cache = originalItemsCache[key],
              let source = cache.dataSource,
              source === dataSource
        else {
            return
        }
        cache.isApplyingConfiguration = false
    }

    // cacheLock must be held by the caller.
    private static func cacheLocked(
        for dataSource: AnyObject
    ) -> BHTSidebarDataSourceCache {
        let key = ObjectIdentifier(dataSource)
        if let existing = originalItemsCache[key],
           let source = existing.dataSource,
           source === dataSource {
            return existing
        }

        let created = BHTSidebarDataSourceCache(dataSource: dataSource)
        originalItemsCache[key] = created
        return created
    }

    private static let setterSymbols = [
        "primaryItems":
            "$s11TwitterDash0B10DataSourceC12primaryItemsSayAA0B11PrimaryItemVGvs",
        "folderItems":
            "$s11TwitterDash0B10DataSourceC11folderItemsSayAA0B10FolderItemVGvs",
        "tertiaryItems":
            "$s11TwitterDash0B10DataSourceC13tertiaryItemsSayAA0B12TertiaryItemVGvs",
    ]

    private static let processHandle = dlopen(nil, RTLD_LAZY)

    private static func symbol(named name: String) -> UnsafeMutableRawPointer? {
        guard let processHandle else {
            return nil
        }
        if let symbol = dlsym(processHandle, name) {
            return symbol
        }
        return dlsym(processHandle, "_" + name)
    }

    private static func callSetter<T>(
        for property: String,
        replacement: T,
        on object: AnyObject
    ) -> Bool {
        guard MemoryLayout<T>.size == MemoryLayout<UInt>.size,
              let symbolName = setterSymbols[property],
              let setterSymbol = symbol(named: symbolName),
              let retainSymbol =
                symbol(named: "swift_retain")
                    ?? symbol(named: "_swift_retain")
        else {
            return false
        }

        let arrayWord = withUnsafeBytes(of: replacement) {
            $0.load(as: UInt.self)
        }
        guard arrayWord != 0,
              let arrayStorage = UnsafeRawPointer(bitPattern: arrayWord)
        else {
            return false
        }

        // A Swift property setter consumes the incoming Array value. Balance
        // that ownership by retaining its storage before entering through the
        // dynamically-resolved ABI function.
        typealias SwiftRetain =
            @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer
        let swiftRetain =
            unsafeBitCast(retainSymbol, to: SwiftRetain.self)
        _ = swiftRetain(arrayStorage)

        BHTInvokeTwitterDashArraySetter(
            arrayWord,
            Unmanaged.passUnretained(object).toOpaque(),
            setterSymbol
        )
        withExtendedLifetime(replacement) {}
        return true
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
        case "blue", "premium", "premium+", "x premium", "get verified",
             "twitter blue":
            return "blue"
        case "history", "bookmarks":
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
