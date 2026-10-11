# 0.7.1 startup crash repair

0.7.0 build 7 can crash immediately after saving Reminders access and on every subsequent launch. Eight device crash reports independently identify the same failure: `EXC_BREAKPOINT` on `com.apple.eventkit.reminders.search`, through `_dispatch_assert_queue_fail`, `_swift_task_checkIsolatedSwift`, and `PlanningService.reminders(sourceIDs:includeCompleted:)`'s completion closure. The reports establish that build 7 was installed. Turning off Calendar and Reminders permissions restores launch without deleting the app.

## Repair

- Create the EventKit completion in an explicitly nonisolated bridge and make its function type `@Sendable`. EventKit can deliver results on its background queue; only immutable `PlanningItem` values pass through the continuation to the app's main actor.
- Reject incomplete native records with a readable error instead of unwrapping missing calendars or dates. An incomplete schedule must not be treated as confirmed availability.
- Keep post-save verification distinct: an unreadable record after submission is still an uncertain outcome, never permission to repeat the write.
- Preserve the bundle identifier, stored conversations, memory, source selections, and installation. The repair requires an in-place 0.7.1 build 8 update, using the same signing account.

## Validation

The existing 161 shared-core tests pass on Windows. Swift source parsing passes; that is not a native compile. Eight new native EventKit tests exercise the same bridge as the app: delivery from a background queue after a MainActor call, overlapping fetches, absent results, incomplete reminders/events, due dates, completion filtering, and version snapshots. Tests create unsaved synthetic objects and do not access personal calendars.

Hosted validation uses one job capped at 15 minutes, running the full shared-core suite plus those eight Mac EventKit tests and building the physical iPhone Release package. No simulator matrix is dispatched for this narrow repair. At the existing estimate of USD 0.062/minute, 16 rounded minutes including cleanup reserve fit within the remaining USD 1.024 allowance. The previous UI evidence belongs to 0.7.0; it does not prove this repaired build works with a real reminder account.

Physical acceptance: install over the current app, verify About 0.7.1 build 8, re-enable Calendar/Reminders, save selected sources, check Today, then close and reopen twice. Keep existing chats. Verify no new app crash report. Until that check passes, leave the connections disabled as the confirmed workaround.

Raw crash reports remain outside the repository. This record contains only the failure signature and app version.

References: [Apple EventKit fetch API](https://developer.apple.com/documentation/eventkit/ekeventstore/fetchreminders(matching:completion:)), [Swift dynamic actor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0423-dynamic-actor-isolation.md).
