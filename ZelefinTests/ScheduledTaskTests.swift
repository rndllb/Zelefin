import JellyfinAPI
import XCTest
@testable import Zelefin

final class ScheduledTaskTests: XCTestCase {
    func testMapsRunningProgressAndLastFailure() throws {
        let dto = TaskInfo(
            category: "Library",
            currentProgressPercentage: 42,
            description: "Scans all folders.",
            id: "scan",
            isHidden: false,
            lastExecutionResult: TaskResult(
                endTimeUtc: Date(timeIntervalSince1970: 200),
                errorMessage: "Disk full",
                startTimeUtc: Date(timeIntervalSince1970: 80),
                status: .failed
            ),
            name: "Scan media library",
            state: .running
        )
        let task = try XCTUnwrap(ScheduledTask(dto: dto))
        XCTAssertEqual(task.name, "Scan media library")
        XCTAssertEqual(task.category, "Library")
        XCTAssertEqual(task.state, .running)
        XCTAssertEqual(try XCTUnwrap(task.progressFraction), 0.42, accuracy: 0.0001)
        XCTAssertEqual(task.progressLabel, "42%")
        XCTAssertEqual(task.stateSubtitle, "Running · 42%")
        XCTAssertTrue(task.canCancel)
        XCTAssertFalse(task.canStart)
        XCTAssertEqual(task.lastStatus, .failed)
        XCTAssertEqual(task.lastError, "Disk full")
        XCTAssertEqual(task.lastDurationLabel, "2:00")
    }

    func testIdleTaskCanStartAndHiddenRunningStaysVisible() throws {
        let idle = try XCTUnwrap(
            ScheduledTask(dto: TaskInfo(category: "Maintenance", id: "clean", name: "Clean transcode cache", state: .idle))
        )
        XCTAssertTrue(idle.canStart)
        XCTAssertFalse(idle.isActive)

        let hidden = try XCTUnwrap(
            ScheduledTask(dto: TaskInfo(id: "plugin", isHidden: true, name: "Plugin task", state: .cancelling))
        )
        XCTAssertTrue(hidden.isHidden)
        XCTAssertTrue(hidden.isActive)
        XCTAssertFalse(hidden.canCancel)
        XCTAssertEqual(hidden.stateSubtitle, "Cancelling")
    }

    func testSortPutsRunningAheadOfIdle() throws {
        let idle = try XCTUnwrap(ScheduledTask(dto: TaskInfo(category: "B", id: "idle", name: "Idle", state: .idle)))
        let running = try XCTUnwrap(ScheduledTask(dto: TaskInfo(category: "A", id: "run", name: "Run", state: .running)))
        XCTAssertEqual(ScheduledTask.sorted([idle, running]).map(\.id), ["run", "idle"])
    }
}
