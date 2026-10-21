import XCTest
import AppKit
import ServiceManagement
@testable import WatchMeSleepCore

private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .enabled
    var registrationStatus: SMAppService.Status = .enabled
    var registers = 0
    var unregisters = 0
    var failure: Error?
    func register() throws {
        registers += 1
        if let failure { throw failure }
        status = registrationStatus
    }
    func unregister() throws {
        unregisters += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testActivationRefreshesExternalLoginItemChanges() {
        let service = FakeLoginItemService()
        let center = NotificationCenter()
        let manager = LaunchAtLoginManager(service: service, notificationCenter: center)
        XCTAssertTrue(manager.isEnabled)

        service.status = .requiresApproval
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(service.registers, 0)
        XCTAssertEqual(service.unregisters, 0)
    }

    func testExplicitRefreshReadsExternalChangesWithoutReactivation() {
        let service = FakeLoginItemService()
        service.status = .notRegistered
        let center = NotificationCenter()
        let manager = LaunchAtLoginManager(service: service, notificationCenter: center)
        XCTAssertFalse(manager.isEnabled)

        service.status = .enabled
        manager.checkStatus() // The Settings window's entry point also refreshes explicitly.

        XCTAssertTrue(manager.isEnabled)
    }

    func testExternalApprovalClearsTheOldApprovalMessage() {
        let service = FakeLoginItemService()
        service.status = .notRegistered
        service.registrationStatus = .requiresApproval
        let center = NotificationCenter()
        let manager = LaunchAtLoginManager(service: service, notificationCenter: center)
        manager.setEnabled(true)
        XCTAssertEqual(service.registers, 1)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertNotNil(manager.errorMessage)

        service.status = .enabled
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(manager.isEnabled)
        XCTAssertNil(manager.errorMessage)
    }

    func testFailedRegistrationStillShowsTheServicesRealStatus() {
        let service = FakeLoginItemService()
        service.status = .notRegistered
        service.failure = NSError(domain: "LoginItemTest", code: 1)
        let manager = LaunchAtLoginManager(service: service, notificationCenter: NotificationCenter())

        manager.setEnabled(true)

        XCTAssertEqual(service.registers, 1)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testFailedUnregistrationKeepsTheErrorWhileTheItemRemainsEnabled() {
        let service = FakeLoginItemService()
        service.failure = NSError(domain: "LoginItemTest", code: 2)
        let center = NotificationCenter()
        let manager = LaunchAtLoginManager(service: service, notificationCenter: center)

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisters, 1)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertNotNil(manager.errorMessage)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertNotNil(manager.errorMessage, "Refreshing must not hide a refused change")
    }
}
