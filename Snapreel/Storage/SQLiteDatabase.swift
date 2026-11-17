import Foundation
import SQLite3

/// Minimal SQLite wrapper: one table of JSON records keyed by (type, id).
/// All calls happen on the main actor through `Library`, so no locking is needed here.
final class SQLiteDatabase {
    enum DatabaseError: LocalizedError {
        case open(String)
        case prepare(String)
        case step(String)

        var errorDescription: String? {
            switch self {
            case .open(let m): return "Couldn't open the library database. \(m)"
            case .prepare(let m), .step(let m): return "The library database had a problem. \(m)"
            }
        }
    }

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.open(message)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("""
            CREATE TABLE IF NOT EXISTS records (
                type TEXT NOT NULL,
                id TEXT NOT NULL,
                json BLOB NOT NULL,
                updated REAL NOT NULL,
                PRIMARY KEY (type, id)
            );
            """)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw DatabaseError.step(message)
        }
    }

    func upsert(type: String, id: String, json: Data) throws {
        let sql = "INSERT INTO records (type, id, json, updated) VALUES (?, ?, ?, ?) ON CONFLICT(type, id) DO UPDATE SET json = excluded.json, updated = excluded.updated;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, type, -1, Self.transient)
        sqlite3_bind_text(statement, 2, id, -1, Self.transient)
        _ = json.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(buffer.count), Self.transient)
        }
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
        try stepDone(statement)
    }

    func delete(type: String, id: String) throws {
        let statement = try prepare("DELETE FROM records WHERE type = ? AND id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, type, -1, Self.transient)
        sqlite3_bind_text(statement, 2, id, -1, Self.transient)
        try stepDone(statement)
    }

    func deleteAll() throws {
        try execute("DELETE FROM records;")
    }

    func rows(type: String) throws -> [Data] {
        let statement = try prepare("SELECT json FROM records WHERE type = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, type, -1, Self.transient)
        var result: [Data] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                let count = Int(sqlite3_column_bytes(statement, 0))
                if let bytes = sqlite3_column_blob(statement, 0), count > 0 {
                    result.append(Data(bytes: bytes, count: count))
                }
            } else if code == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.step(lastError)
            }
        }
        return result
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.prepare(lastError)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        let code = sqlite3_step(statement)
        if code != SQLITE_DONE {
            throw DatabaseError.step(lastError)
        }
    }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}
