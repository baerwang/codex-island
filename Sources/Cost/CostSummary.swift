import Foundation

/// Pure aggregation for the cost screen — a single pass over a flat
/// `[TokenEvent]` stream that splits it into today / this-month / rolling-5h /
/// rolling-7d windows, per-model breakdowns, and sparkline buckets.
///
/// Lives as a free `enum` so the detached refresh task in `CostStore` can call
/// it off the main actor without touching `@MainActor` state. `now` is
/// injectable so the window boundaries are testable.
enum CostSummary {
    private struct SourceDayKey: Hashable {
        let sourceID: String
        let dayOffset: Int
    }

    private struct DailyTokenAccumulator {
        var tokens = 0
        var billableTokens = 0
    }

    private struct ProjectAccumulator {
        var name: String
        var sourceID: String?
        var sourceName: String?
        var todayDollars = 0.0
        var monthDollars = 0.0
        var todayTokens = 0
        var monthTokens = 0
        var todayBillable = 0
        var monthBillable = 0
    }

    static func summarize(events: [TokenEvent], now: Date = Date()) -> ProviderCost {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startOfDay = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfDay
        let currentHour = cal.dateComponents([.hour], from: now).hour ?? 0
        let currentDay = (cal.dateComponents([.day], from: now).day ?? 1) - 1
        let historyDays = yearHistoryDays(now: now)
        let historyStart = cal.date(
            byAdding: .day,
            value: -(historyDays - 1),
            to: startOfDay
        ) ?? startOfDay
        // Rolling windows for per-model breakdown — approximate the live
        // tile windows. We don't know the server's exact window alignment
        // for either, so "last N hours from now" is the practical proxy.
        // 5h matches Anthropic's rate-limit window; 7d matches both
        // providers' weekly tile.
        let recentStart = now.addingTimeInterval(-5 * 3600)
        let weekStart = now.addingTimeInterval(-7 * 24 * 3600)

        var todayDollars = 0.0, todayTokens = 0, todayBillable = 0
        var monthDollars = 0.0, monthTokens = 0, monthBillable = 0
        var hourlyBuckets = Array(repeating: 0.0, count: currentHour + 1)
        var dailyBuckets = Array(repeating: 0.0, count: currentDay + 1)
        var historyBySourceDay: [SourceDayKey: DailyTokenAccumulator] = [:]
        // Filtered to non-zero token events so handshake/stub rows don't
        // show up as "unpriced" warnings — the user only cares about
        // models that actually moved tokens.
        var todayUnknown: Set<String> = []
        var monthUnknown: Set<String> = []
        // Per-model input+output, all-token, and dollar totals within the
        // recent window. Both token totals are retained so the Models page
        // can follow TokenCountModeStore without another log scan.
        var recentTokensByModel: [String: Int] = [:]
        var recentAllTokensByModel: [String: Int] = [:]
        var recentDollarsByModel: [String: Double] = [:]
        // Same shape, weekly window. Two windows in one pass costs an
        // extra `>=` per event — cheap relative to JSON parsing upstream.
        var weekTokensByModel: [String: Int] = [:]
        var weekAllTokensByModel: [String: Int] = [:]
        var weekDollarsByModel: [String: Double] = [:]
        var projects: [String: ProjectAccumulator] = [:]
        // A provider emits the same cwd on every token event. Resolving
        // symlinks through Foundation for every row dominated warm scans and
        // produced gigabytes of transient allocator traffic on large logs.
        // Resolve each distinct raw path once per aggregation pass instead.
        var resolvedProjectPaths: [String: (path: String, name: String)] = [:]
        var unresolvedProjectPaths = Set<String>()

        // Drop events older than every window's start. Using `min(...)`
        // matters here because the rolling 7-day window straddles month
        // boundaries: on May 3, weekStart is Apr 26, but `monthStart` is
        // May 1, so a `>= monthStart` guard would silently filter out
        // Apr 26–30 from the weekly slice. The 5h slice never had this
        // problem (5h ⊂ today ⊂ month), but adding weekly broke the
        // assumption — keep the broader guard.
        let earliestStart = min(monthStart, weekStart, historyStart)
        for event in events {
            // A clock-skewed local log must not make today's/month-to-date
            // spend jump ahead of the current wall clock.
            guard event.timestamp >= earliestStart, event.timestamp <= now else { continue }
            let cost = Pricing.cost(for: event)
            // Two parallel running totals: `tokens` is the wire-level sum
            // (ccusage parity); `billable` is input + output only, matching
            // Anthropic's claude.ai stats panel which excludes cache tokens.
            // Persisting both lets the Settings toggle flip the displayed
            // figure instantly without re-scanning session logs.
            let billable = event.inputTokens + event.outputTokens
            let tokens = billable + event.cacheCreationTokens + event.cacheReadTokens
            let isUnpriced = tokens > 0 && !Pricing.isKnown(event.model)
            let resolvedProject: (path: String, name: String)? = {
                guard let rawProject = event.projectID else { return nil }
                if let cached = resolvedProjectPaths[rawProject] { return cached }
                if unresolvedProjectPaths.contains(rawProject) { return nil }
                guard let path = canonicalProjectID(rawProject) else {
                    unresolvedProjectPaths.insert(rawProject)
                    return nil
                }
                let resolved = (path: path, name: URL(fileURLWithPath: path).lastPathComponent)
                resolvedProjectPaths[rawProject] = resolved
                return resolved
            }()
            let projectID = "\(event.sourceID ?? "local")::\(resolvedProject?.path ?? "unattributed")"
            let projectName = resolvedProject?.name
                ?? event.projectName.flatMap { $0.isEmpty ? nil : $0 }
                ?? "Unattributed"
            let sourceID = event.sourceID
            let sourceName = event.sourceName

            if event.timestamp >= historyStart {
                let eventDay = cal.startOfDay(for: event.timestamp)
                let dayOffset = cal.dateComponents([.day], from: historyStart, to: eventDay).day ?? -1
                if (0..<historyDays).contains(dayOffset) {
                    let key = SourceDayKey(
                        sourceID: event.sourceID ?? "", dayOffset: dayOffset
                    )
                    historyBySourceDay[key, default: DailyTokenAccumulator()].tokens += tokens
                    historyBySourceDay[key, default: DailyTokenAccumulator()].billableTokens += billable
                }
            }

            // Month aggregation gated separately now that the outer guard
            // is `min(monthStart, weekStart)` (so previous-month events
            // can reach the weekly slice).
            if event.timestamp >= monthStart {
                monthDollars += cost
                monthTokens += tokens
                monthBillable += billable
                let day = (cal.dateComponents([.day], from: event.timestamp).day ?? 1) - 1
                if day < dailyBuckets.count { dailyBuckets[day] += cost }
                if isUnpriced { monthUnknown.insert(event.model) }
                var project = projects[projectID] ?? ProjectAccumulator(name: projectName, sourceID: sourceID, sourceName: sourceName)
                project.monthDollars += cost
                project.monthTokens += tokens
                project.monthBillable += billable
                projects[projectID] = project
            }

            // Today is a strict subset of month
            if event.timestamp >= startOfDay {
                todayDollars += cost
                todayTokens += tokens
                todayBillable += billable
                let hour = cal.dateComponents([.hour], from: event.timestamp).hour ?? 0
                if hour < hourlyBuckets.count { hourlyBuckets[hour] += cost }
                if isUnpriced { todayUnknown.insert(event.model) }
                var project = projects[projectID] ?? ProjectAccumulator(name: projectName, sourceID: sourceID, sourceName: sourceName)
                project.todayDollars += cost
                project.todayTokens += tokens
                project.todayBillable += billable
                projects[projectID] = project
            }

            // Weekly rolling window slice — superset of recent, subset of
            // month (when month is short). Keep the exact model identifier
            // recorded by the local log. Model snapshots and point releases
            // are distinct activity and must not be folded into a base model
            // on the Models page.
            if event.timestamp >= weekStart {
                let modelID = event.model
                if billable > 0 {
                    weekTokensByModel[modelID, default: 0] += billable
                }
                if tokens > 0 {
                    weekAllTokensByModel[modelID, default: 0] += tokens
                }
                if cost > 0 {
                    weekDollarsByModel[modelID, default: 0] += cost
                }

                // 5h rolling window slice — strict subset of weekly.
                if event.timestamp >= recentStart {
                    if billable > 0 {
                        recentTokensByModel[modelID, default: 0] += billable
                    }
                    if tokens > 0 {
                        recentAllTokensByModel[modelID, default: 0] += tokens
                    }
                    if cost > 0 {
                        recentDollarsByModel[modelID, default: 0] += cost
                    }
                }
            }
        }

        let recentRows = modelRows(
            tokensByModel: recentTokensByModel,
            allTokensByModel: recentAllTokensByModel,
            dollarsByModel: recentDollarsByModel
        )
        let weekRows = modelRows(
            tokensByModel: weekTokensByModel,
            allTokensByModel: weekAllTokensByModel,
            dollarsByModel: weekDollarsByModel
        )

        return ProviderCost(
            today: CostWindow(
                dollars: todayDollars,
                tokens: todayTokens,
                billableTokens: todayBillable,
                series: runningSum(hourlyBuckets),
                label: "Today",
                error: nil,
                unknownModels: todayUnknown.sorted()
            ),
            month: CostWindow(
                dollars: monthDollars,
                tokens: monthTokens,
                billableTokens: monthBillable,
                series: runningSum(dailyBuckets),
                label: CostBucketing.currentMonthLabel(),
                error: nil,
                unknownModels: monthUnknown.sorted()
            ),
            recentByModel: recentRows,
            weekByModel: weekRows,
            dailyTokens: dailyTokenBucketsBySourceDay(
                start: historyStart,
                history: historyBySourceDay,
                calendar: cal
            ),
            projects: projects.map { key, value in
                ProjectUsageRow(
                    id: key, name: value.name, sourceID: value.sourceID, sourceName: value.sourceName,
                    todayDollars: value.todayDollars, monthDollars: value.monthDollars,
                    todayTokens: value.todayTokens, monthTokens: value.monthTokens,
                    todayBillableTokens: value.todayBillable, monthBillableTokens: value.monthBillable
                )
            }
            .sorted {
                if $0.monthDollars != $1.monthDollars { return $0.monthDollars > $1.monthDollars }
                return $0.monthTokens > $1.monthTokens
            }
        )
    }

    static func yearHistoryDays(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        let yearStart = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
        let yearDays = (cal.dateComponents([.day], from: yearStart, to: today).day ?? 0) + 1
        return max(1, yearDays)
    }

    private static func canonicalProjectID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func dailyTokenBucketsBySourceDay(
        start: Date,
        history: [SourceDayKey: DailyTokenAccumulator],
        calendar: Calendar
    ) -> [DailyTokenBucket] {
        history.keys.sorted {
            if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
            return $0.dayOffset < $1.dayOffset
        }.compactMap { key in
            guard let accumulated = history[key],
                  accumulated.tokens > 0 || accumulated.billableTokens > 0
            else { return nil }
            let day = calendar.date(byAdding: .day, value: key.dayOffset, to: start) ?? start
            return DailyTokenBucket(
                dayStart: day,
                tokens: accumulated.tokens,
                billableTokens: accumulated.billableTokens,
                sourceID: key.sourceID.isEmpty ? nil : key.sourceID
            )
        }
    }

    /// Build sorted `ModelUsageRow`s from the parallel per-model maps
    /// for a given window. Shared between the 5h and weekly slices so
    /// both stay perfectly consistent in shape, sorting, and percent-share
    /// computation.
    private static func modelRows(
        tokensByModel: [String: Int],
        allTokensByModel: [String: Int],
        dollarsByModel: [String: Double]
    ) -> [ModelUsageRow] {
        let totalTokens = tokensByModel.values.reduce(0, +)
        let totalDollars = dollarsByModel.values.reduce(0, +)
        let modelIDs = Set(tokensByModel.keys)
            .union(allTokensByModel.keys)
            .union(dollarsByModel.keys)
        return modelIDs.map { modelID in
            let tokens = tokensByModel[modelID] ?? 0
            let allTokens = allTokensByModel[modelID] ?? 0
            let dollars = dollarsByModel[modelID] ?? 0
            return ModelUsageRow(
                model: modelID,
                displayName: prettyModelName(modelID),
                tokens: tokens,
                allTokens: allTokens,
                dollars: dollars,
                percent: totalTokens > 0 ? Double(tokens) / Double(totalTokens) : 0,
                dollarPercent: totalDollars > 0 ? dollars / totalDollars : 0
            )
        }
        .sorted {
            // Tokens primary, dollars secondary — handles cache-read-only
            // rows (zero billable tokens, non-zero dollars) by sinking
            // them to the bottom but not disappearing.
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.dollars > $1.dollars
        }
    }

    /// Format an exact log model id without consulting a client-side model
    /// list. Unknown future model families therefore appear immediately.
    private static func prettyModelName(_ modelID: String) -> String {
        // Anthropic: "claude-opus-4-7" → "Opus 4.7"
        if modelID.hasPrefix("claude-") {
            let trimmed = String(modelID.dropFirst("claude-".count))
            // Split at first dash, then collapse remaining dashes into dots
            // so "opus-4-7" → "opus.4.7" → "Opus 4.7".
            guard let dash = trimmed.firstIndex(of: "-") else {
                return trimmed.capitalized
            }
            let family = String(trimmed[..<dash]).capitalized
            let version = trimmed[trimmed.index(after: dash)...]
                .replacingOccurrences(of: "-", with: ".")
            return "\(family) \(version)"
        }
        // OpenAI: keep as-is, just uppercase the GPT prefix.
        if modelID.hasPrefix("gpt-") {
            return modelID.replacingOccurrences(of: "gpt-", with: "GPT-")
        }
        // OpenAI reasoning family ("o3-pro", "o4-mini-high", etc.) — already
        // short and conventional, capitalize only the leading letter so it
        // matches the typographic weight of "GPT-..." / "Opus 4.7".
        if let first = modelID.first, first == "o", modelID.count > 1,
           modelID.dropFirst().first?.isNumber == true {
            return modelID.prefix(1).uppercased() + modelID.dropFirst()
        }
        return modelID
    }

    private static func runningSum(_ values: [Double]) -> [Double] {
        var out = [Double]()
        out.reserveCapacity(values.count)
        var sum = 0.0
        for v in values { sum += v; out.append(sum) }
        return out
    }
}
