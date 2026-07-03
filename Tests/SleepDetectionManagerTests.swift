import XCTest
import Vision
@testable import WatchMeSleepCore

final class SleepDetectionManagerTests: XCTestCase {
    var sleepManager: SleepDetectionManager!
    
    override func setUp() {
        super.setUp()
        sleepManager = SleepDetectionManager.shared
        sleepManager.setCameraModeEnabled(false)
    }
    
    override func tearDown() {
        sleepManager.setCameraModeEnabled(false)
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        XCTAssertFalse(sleepManager.isCameraModeEnabled, "Camera mode should be disabled initially")
        XCTAssertFalse(sleepManager.isSessionRunning, "Session should not be running initially")
        XCTAssertFalse(sleepManager.isUserAsleep, "User should not be marked as asleep initially")
        XCTAssertEqual(sleepManager.statusMessage, "Camera tracking is off.", "Initial status message should be set")
    }
    
    // MARK: - Camera Mode Tests
    
    func testSetCameraModeEnabled() {
        // When
        sleepManager.setCameraModeEnabled(true)
        
        // Then
        XCTAssertTrue(sleepManager.isCameraModeEnabled, "Camera mode should be enabled")
    }
    
    func testSetCameraModeDisabled() {
        // Given
        sleepManager.setCameraModeEnabled(true)
        XCTAssertTrue(sleepManager.isCameraModeEnabled)
        
        // When
        sleepManager.setCameraModeEnabled(false)
        
        // Then
        XCTAssertFalse(sleepManager.isCameraModeEnabled, "Camera mode should be disabled")
        XCTAssertFalse(sleepManager.isUserAsleep, "User sleep state should be reset")
        XCTAssertEqual(sleepManager.statusMessage, "Camera tracking is off.", "Status message should be reset")
    }
    
    // MARK: - Eye Aspect Ratio (EAR) Tests
    
    // Note: EAR calculation tests are skipped as VNFaceLandmarkRegion2D cannot be mocked
    // (it's a non-open class from Vision framework).
    // EAR formula correctness is validated through manual testing with camera.
    
    // MARK: - Status Message Tests
    
    func testStatusMessageWhenCameraDisabled() {
        // Given
        sleepManager.setCameraModeEnabled(false)
        
        // Then
        XCTAssertEqual(sleepManager.statusMessage, "Camera tracking is off.")
    }
    
    // MARK: - Singleton Pattern Tests
    
    func testSingletonInstance() {
        let instance1 = SleepDetectionManager.shared
        let instance2 = SleepDetectionManager.shared
        
        XCTAssertTrue(instance1 === instance2, "Should return the same instance")
    }
}

// MARK: - Mock Objects
// Note: VNFaceLandmarkRegion2D is a non-open class and cannot be mocked or subclassed
// for testing. EAR calculation is tested manually with actual camera input.

