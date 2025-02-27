import Foundation

enum AppConfig {
    static let SCREENSHOT_MODE = false
    static let version = "2.0"
    
    struct MockDevice {
        let name: String
        let isConnected: Bool
        let isHeartRateDevice: Bool
    }
    
    enum MockData {
        static let heartRate = "71"
        static let batteryLevel = 83
        static let lastUpdateSeconds = 0.4
        static let devices = [
            MockDevice(name: "HRMPro+:893594", isConnected: true, isHeartRateDevice: true),
            MockDevice(name: "AirPods Pro #3", isConnected: false, isHeartRateDevice: false),
            MockDevice(name: "AirPods Pro #3", isConnected: false, isHeartRateDevice: false),
            MockDevice(name: "GVH5106_6313", isConnected: false, isHeartRateDevice: false),
            MockDevice(name: "MacBook Pro", isConnected: false, isHeartRateDevice: false)
        ]
    }
}


    

