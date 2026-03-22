import Foundation
import SQLite3

extension Notification.Name {
    static let historyStoreDidChange = Notification.Name("Type4Me.historyStoreDidChange")
}

actor HistoryStore {

    private var db: OpaquePointer?

    init(path: String? = nil) {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent("Type4Me", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            dbPath = appSupport.appendingPathComponent("history.db").path
        }

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            let sql = """
            CREATE TABLE IF NOT EXISTS recognition_history (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                duration_seconds REAL,
                raw_text TEXT NOT NULL,
                processing_mode TEXT,
                processed_text TEXT,
                final_text TEXT NOT NULL,
                status TEXT NOT NULL
            );
            """
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    // MARK: - CRUD

    func insert(_ record: HistoryRecord) {
        let sql = """
        INSERT OR REPLACE INTO recognition_history
        (id, created_at, duration_seconds, raw_text, processing_mode, processed_text, final_text, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let iso = ISO8601DateFormatter()
        bind(stmt, 1, record.id)
        bind(stmt, 2, iso.string(from: record.createdAt))
        sqlite3_bind_double(stmt, 3, record.durationSeconds)
        bind(stmt, 4, record.rawText)
        bindOptional(stmt, 5, record.processingMode)
        bindOptional(stmt, 6, record.processedText)
        bind(stmt, 7, record.finalText)
        bind(stmt, 8, record.status)
        if sqlite3_step(stmt) == SQLITE_DONE {
            postDidChangeNotification()
        }
    }

    func fetchAll(limit: Int? = nil, offset: Int = 0) -> [HistoryRecord] {
        let sql: String
        if let limit {
            sql = "SELECT * FROM recognition_history ORDER BY created_at DESC LIMIT \(limit) OFFSET \(offset);"
        } else {
            sql = "SELECT * FROM recognition_history ORDER BY created_at DESC;"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let iso = ISO8601DateFormatter()
        var records: [HistoryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            records.append(HistoryRecord(
                id: column(stmt, 0),
                createdAt: iso.date(from: column(stmt, 1)) ?? Date(),
                durationSeconds: sqlite3_column_double(stmt, 2),
                rawText: column(stmt, 3),
                processingMode: optionalColumn(stmt, 4),
                processedText: optionalColumn(stmt, 5),
                finalText: column(stmt, 6),
                status: column(stmt, 7)
            ))
        }
        return records
    }

    func delete(id: String) {
        let sql = "DELETE FROM recognition_history WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id)
        if sqlite3_step(stmt) == SQLITE_DONE {
            postDidChangeNotification()
        }
    }

    func deleteAll() {
        if sqlite3_exec(db, "DELETE FROM recognition_history;", nil, nil, nil) == SQLITE_OK {
            postDidChangeNotification()
        }
    }

    // MARK: - SQLite Helpers

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func bindOptional(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bind(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(stmt, index))
    }

    private func optionalColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_text(stmt, index).map { String(cString: $0) }
    }

    private func postDidChangeNotification() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        }
    }
}
