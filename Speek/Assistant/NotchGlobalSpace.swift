import AppKit

/// Dedicated overlay Space, following Boring Notch's NotchSpaceManager architecture.
/// Reference: https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/private/CGSSpace.swift
/// These WindowServer entry points are private; resolve all of them before use.
@MainActor
final class NotchGlobalSpace {
    private typealias Connection = @convention(c) () -> UInt
    private typealias Create = @convention(c) (UInt, Int, CFDictionary?) -> UInt64
    private typealias Destroy = @convention(c) (UInt, UInt64) -> Void
    private typealias Level = @convention(c) (UInt, UInt64, Int) -> Void
    private typealias Visibility = @convention(c) (UInt, CFArray) -> Void
    private typealias Membership = @convention(c) (UInt, CFArray, CFArray) -> Void

    private let handle: UnsafeMutableRawPointer
    private let connection: UInt
    private var space: UInt64
    private let destroy: Destroy
    private let show: Visibility
    private let hide: Visibility
    private let remove: Membership
    private let windowID: Int
    private var lockObservers: [NSObjectProtocol] = []

    init?(window: NSWindow) {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func resolve<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let getConnection = resolve("_CGSDefaultConnection", as: Connection.self),
              let create = resolve("CGSSpaceCreate", as: Create.self),
              let destroy = resolve("CGSSpaceDestroy", as: Destroy.self),
              let level = resolve("CGSSpaceSetAbsoluteLevel", as: Level.self),
              let show = resolve("CGSShowSpaces", as: Visibility.self),
              let hide = resolve("CGSHideSpaces", as: Visibility.self),
              let add = resolve("CGSAddWindowsToSpaces", as: Membership.self),
              let remove = resolve("CGSRemoveWindowsFromSpaces", as: Membership.self) else {
            dlclose(handle)
            return nil
        }
        let connection = getConnection()
        let space = create(connection, 1, nil)
        guard space != 0 else { dlclose(handle); return nil }
        self.handle = handle
        self.connection = connection
        self.space = space
        self.destroy = destroy
        self.show = show
        self.hide = hide
        self.remove = remove
        self.windowID = window.windowNumber
        level(connection, space, Int(Int32.max))
        add(connection, [windowID] as CFArray, [space] as CFArray)
        show(connection, [space] as CFArray)
        let center = DistributedNotificationCenter.default()
        for (name, visible) in [("com.apple.screenIsLocked", false), ("com.apple.screenIsUnlocked", true)] {
            lockObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setVisible(visible) }
            })
        }
        NSLog("Speek notch attached to dedicated overlay Space")
    }

    private func setVisible(_ visible: Bool) {
        guard space != 0 else { return }
        if visible { show(connection, [space] as CFArray) }
        else { hide(connection, [space] as CFArray) }
    }

    func close() {
        guard space != 0 else { return }
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        lockObservers.removeAll()
        remove(connection, [windowID] as CFArray, [space] as CFArray)
        hide(connection, [space] as CFArray)
        destroy(connection, space)
        space = 0
        dlclose(handle)
    }
}
