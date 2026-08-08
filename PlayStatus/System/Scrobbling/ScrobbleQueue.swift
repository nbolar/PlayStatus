import Foundation

/// Pending scrobbles, kept on disk until Last.fm accepts them.
///
/// Losing scrobbles is the failure users notice and complain about, and Last.fm is
/// unreachable often enough that "send once and hope" is not good enough. Everything here
/// exists to make the queue survive being offline, being quit, and being rate limited.
actor ScrobbleQueue {
    static let shared = ScrobbleQueue()

    /// An indefinitely offline user must not grow this without bound. At the ceiling the
    /// oldest go first — a month-old scrobble matters less than this afternoon's.
    static let maximumPending = 2000

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let fileURL: URL

    private var pending: [ScrobbleSubmission] = []
    private var loaded = false

    /// Set after a transient failure; nothing is sent again until it passes.
    private var retryNotBefore: Date?
    private var consecutiveFailures = 0

    init(directoryName: String = "Scrobbles") {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportURL
            .appendingPathComponent("PlayStatus", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        fileURL = rootURL.appendingPathComponent("pending.json", isDirectory: false)
    }

    // MARK: State

    func pendingCount() -> Int {
        ensureLoaded()
        return pending.count
    }

    func enqueue(_ submission: ScrobbleSubmission) {
        ensureLoaded()
        guard submission.isSubmittable else { return }
        pending.append(submission)
        if pending.count > Self.maximumPending {
            pending.removeFirst(pending.count - Self.maximumPending)
        }
        persist()
    }

    func clear() {
        ensureLoaded()
        pending.removeAll()
        retryNotBefore = nil
        consecutiveFailures = 0
        persist()
    }

    /// Wakes the queue early — used when the user asks for a retry by hand.
    func clearBackoff() {
        retryNotBefore = nil
        consecutiveFailures = 0
    }

    // MARK: Flushing

    enum FlushOutcome: Equatable {
        case idle
        case sent(Int)
        case waiting
        case failed(LastFMError)
    }

    /// Sends as much of the queue as Last.fm will take, oldest first.
    ///
    /// - Parameter sessionKey: the user's Last.fm session key.
    @discardableResult
    func flush(sessionKey: String, client: LastFMClient = .shared) async -> FlushOutcome {
        ensureLoaded()
        guard !pending.isEmpty else { return .idle }
        if let retryNotBefore, Date() < retryNotBefore { return .waiting }

        var sentCount = 0
        // Oldest first, so a queue that outgrew one batch drains in listening order.
        while !pending.isEmpty {
            let batch = Array(pending.prefix(50))
            do {
                _ = try await client.scrobble(batch, sessionKey: sessionKey)
                // Removed only after Last.fm confirms, so a crash mid-flush replays rather
                // than silently dropping.
                pending.removeFirst(batch.count)
                sentCount += batch.count
                persist()
            } catch let error as LastFMError {
                switch error {
                case .transient:
                    scheduleBackoff()
                    persist()
                    return sentCount > 0 ? .sent(sentCount) : .failed(error)
                case .authenticationRequired, .notConfigured:
                    // Keep the queue: reconnecting should not cost the user their scrobbles.
                    scheduleBackoff()
                    return .failed(error)
                case .permanent:
                    // This batch will never be accepted. Dropping it is the only way to stop
                    // it blocking everything queued behind it.
                    #if DEBUG
                    NSLog("PlayStatus scrobble: dropping %d rejected scrobbles: %@",
                          batch.count, error.message)
                    #endif
                    pending.removeFirst(batch.count)
                    persist()
                }
            } catch {
                scheduleBackoff()
                return .failed(.transient(error.localizedDescription))
            }
        }

        consecutiveFailures = 0
        retryNotBefore = nil
        return sentCount > 0 ? .sent(sentCount) : .idle
    }

    private func scheduleBackoff() {
        consecutiveFailures += 1
        // 30s, 1m, 2m, 4m … capped at 30 minutes.
        let seconds = min(30 * pow(2, Double(consecutiveFailures - 1)), 1800)
        retryNotBefore = Date().addingTimeInterval(seconds)
        #if DEBUG
        NSLog("PlayStatus scrobble: backing off %.0fs after %d failures", seconds, consecutiveFailures)
        #endif
    }

    // MARK: Persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? Self.decoder.decode([ScrobbleSubmission].self, from: data) else {
            #if DEBUG
            NSLog("PlayStatus scrobble: pending queue unreadable, starting empty")
            #endif
            return
        }
        pending = decoded
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(pending)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            NSLog("PlayStatus scrobble: queue write failed %@", String(describing: error))
            #endif
        }
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
