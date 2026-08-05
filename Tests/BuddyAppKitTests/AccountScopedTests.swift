//
//  AccountScopedTests.swift
//  BuddyAppKitTests
//
//  Ported from the RankBuddy merge-loader suite (#17): account tagging, partial results
//  when an account fails, all-fail behaviour, and cross-account id distinctness, plus the
//  generic AccountScoped id derivation (computed vs explicit).
//

import BuddyAppKit
import Foundation
import Testing

@MainActor
struct AccountScopedTests {
    private struct Account: Identifiable, Hashable, Sendable {
        let id: UUID
        init(_ id: UUID = UUID()) { self.id = id }
    }

    private struct Item: Identifiable, Hashable, Sendable {
        let id: String
    }

    private struct StringAccount: Identifiable {
        let id: String
    }

    private struct Boom: Error {}

    // MARK: - AccountScoped id

    @Test
    func `the derived id namespaces the item id by account, staying distinct across accounts`() {
        let accA = Account()
        let accB = Account()
        let rowA = AccountScoped(account: accA, item: Item(id: "dup"))
        let rowB = AccountScoped(account: accB, item: Item(id: "dup"))
        #expect(rowA.id == "36:\(accA.id)3:dup")
        #expect(rowA.id != rowB.id)
    }

    @Test
    func `derived ids cannot collide when components contain delimiters`() {
        let accountContainsDelimiter = AccountScoped(
            account: StringAccount(id: "a|b"), item: Item(id: "c")
        )
        let itemContainsDelimiter = AccountScoped(
            account: StringAccount(id: "a"), item: Item(id: "b|c")
        )

        #expect(accountContainsDelimiter.id == "3:a|b1:c")
        #expect(itemContainsDelimiter.id == "1:a3:b|c")
        #expect(accountContainsDelimiter.id != itemContainsDelimiter.id)
    }

    @Test
    func `an explicit id overrides the derived one`() {
        let row = AccountScoped(account: Account(), item: Item(id: "ignored"), id: "slug-123")
        #expect(row.id == "slug-123")
    }

    // MARK: - MergedLoader.firstPages

    @Test
    func `merges items tagged by their account, in account order`() async throws {
        let accA = Account()
        let accB = Account()
        let merged = try await MergedLoader.firstPages(accounts: [accA, accB]) { acct in
            acct.id == accA.id ? [Item(id: "1"), Item(id: "2")] : [Item(id: "3")]
        }
        #expect(merged.map(\.item.id) == ["1", "2", "3"])
        #expect(merged.count(where: { $0.account.id == accA.id }) == 2)
        #expect(merged.last?.account.id == accB.id)
    }

    @Test
    func `a failing account is skipped but the others still return`() async throws {
        let good = Account()
        let bad = Account()
        let merged = try await MergedLoader.firstPages(accounts: [bad, good]) { acct in
            if acct.id == bad.id { throw Boom() }
            return [Item(id: "ok")]
        }
        #expect(merged.map(\.item.id) == ["ok"])
        #expect(merged.first?.account.id == good.id)
    }

    @Test
    func `it throws only when every account fails`() async {
        await #expect(throws: Boom.self) {
            _ = try await MergedLoader.firstPages(accounts: [Account(), Account()]) { _ -> [Item] in
                throw Boom()
            }
        }
    }

    @Test
    func `no accounts yields an empty list`() async throws {
        let merged = try await MergedLoader.firstPages(accounts: [Account]()) { _ in [Item(id: "x")] }
        #expect(merged.isEmpty)
    }

    @Test
    func `the same item id in two accounts stays distinct`() async throws {
        let merged = try await MergedLoader.firstPages(accounts: [Account(), Account()]) { _ in
            [Item(id: "dup")]
        }
        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)).count == 2)
    }
}
