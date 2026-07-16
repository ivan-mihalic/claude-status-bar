// Sources/ClaudeStatusBarApp/Accounts/BrowserOpener.swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public protocol BrowserOpener: Sendable { func open(_ url: URL) }

public struct SystemBrowserOpener: BrowserOpener {
    public init() {}
    public func open(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
