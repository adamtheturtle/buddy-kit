//
//  AccountScoped.swift
//  BuddyAppKit
//
//  The data seam for multi-account "merged" lists shared by the buddy apps: an item
//  tagged with the account it came from, and a loader that fans a fetch out across
//  accounts and tags every result. Generic over both the account and the item, with all
//  conformances conditional, so each app supplies its own (Sendable or not) account and
//  item models. View, routing, detail, drag and filtering stay app-side.
//

import Foundation

/// An item paired with the account it came from, so a merged row knows which account to
/// navigate, fetch detail, or act against. Generic over the account and item models with
/// no forced conformances; the conditional extensions below add `Identifiable`/`Sendable`/
/// `Hashable`/`Equatable` only when both sides support them.
public nonisolated struct AccountScoped<Account, Item> {
    public let account: Account
    public let item: Item
    /// An explicit row id, when the item's own id is already globally unique (e.g. a slug)
    /// and the app wants to keep it as the row identity. When nil, `id` is derived as
    /// a length-prefixed pair, which stays distinct even when either component contains
    /// separators.
    private let explicitID: String?

    public init(account: Account, item: Item) {
        self.account = account
        self.item = item
        explicitID = nil
    }

    public init(account: Account, item: Item, id: String) {
        self.account = account
        self.item = item
        explicitID = id
    }
}

extension AccountScoped: Identifiable where Account: Identifiable, Item: Identifiable {
    /// Unique across accounts: the same item id in two accounts stays distinct, unless an
    /// explicit globally-unique id was supplied.
    public var id: String {
        if let explicitID { return explicitID }

        let accountID = String(describing: account.id)
        let itemID = String(describing: item.id)
        return "\(accountID.utf8.count):\(accountID)\(itemID.utf8.count):\(itemID)"
    }
}

extension AccountScoped: Sendable where Account: Sendable, Item: Sendable {}
extension AccountScoped: Equatable where Account: Equatable, Item: Equatable {}
extension AccountScoped: Hashable where Account: Hashable, Item: Hashable {}

/// Loads the first page of a collection from several accounts and merges the results.
public enum MergedLoader {
    /// Fetches each account's first page, tagging every item with its account. Accounts
    /// whose fetch fails are skipped so one failing account never discards the others'
    /// results (partial results); throws only when **every** account fails, so the list
    /// surfaces an error instead of a misleading empty state. No accounts → an empty list.
    @MainActor
    public static func firstPages<Account, Item>(
        accounts: [Account],
        fetch: @MainActor (Account) async throws -> [Item]
    ) async throws -> [AccountScoped<Account, Item>] {
        var scoped: [AccountScoped<Account, Item>] = []
        var firstError: Error?
        var anySuccess = false

        for account in accounts {
            try Task.checkCancellation()
            do {
                let items = try await fetch(account)
                anySuccess = true
                scoped += items.map { AccountScoped(account: account, item: $0) }
            } catch {
                if error is CancellationError { throw error }
                try Task.checkCancellation()
                if firstError == nil { firstError = error }
            }
        }

        try Task.checkCancellation()
        if !anySuccess, let firstError {
            throw firstError
        }
        return scoped
    }
}
