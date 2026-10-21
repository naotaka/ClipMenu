import Foundation
import SwiftData
import SQLite3
import Darwin

/// Coordinates clearing with delayed clipboard/action work. These guarantees
/// cover the app's live store; APFS snapshots and third-party copies are outside
/// its control. Never claim forensic erasure of SSD blocks or backups.
@MainActor
enum HistoryErasure {
    private(set) static var generation: UInt64 = 0

    static func begin() { generation &+= 1 }

    static func compactStore(in context: ModelContext) throws {
        guard context.container.configurations.contains(where: { !$0.isStoredInMemoryOnly }) else { return }
        if #available(macOS 15, *) {
            // SwiftData keeps a separate change log even after model deletion.
            // No part of this app consumes that log or syncs it to another device.
            try context.deleteHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        }
        for configuration in context.container.configurations where !configuration.isStoredInMemoryOnly {
            try compactSQLite(at: configuration.url)
        }
    }

    static func compactSQLite(at url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
        // Foundation can preserve macOS's /var alias even after resolving
        // symlinks. SQLite NOFOLLOW requires the actual canonical parent path.
        guard let parent = realpath(url.deletingLastPathComponent().path, nil) else {
            throw ErasureError.couldNotCompact
        }
        defer { free(parent) }
        let path = String(cString: parent) + "/" + url.lastPathComponent
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw ErasureError.couldNotCompact
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)
        // VACUUM rebuilds the live database without deleted record contents.
        // TRUNCATE is essential: a WAL reset alone leaves old bytes readable.
        for sql in ["PRAGMA temp_store = MEMORY", "PRAGMA secure_delete = ON", "VACUUM"] {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw ErasureError.couldNotCompact
            }
        }
        guard sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil) == SQLITE_OK else {
            throw ErasureError.couldNotCompact
        }
    }

    enum ErasureError: LocalizedError {
        case couldNotCompact
        var errorDescription: String? {
            "The saved database could not be fully cleared. Close other copies of clip'M and try Clear History again."
        }
    }
}
