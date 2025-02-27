import SwiftUI
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    @Published var heartRatePeripheral: CBPeripheral?
    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String, isHeartRateDevice: Bool)] = []
    private var scanStopTimer: Timer?
    private var pendingConnection: CBPeripheral?
    
    #if DEBUG
    private let debugScanAllDevices = true
    #else
    private let debugScanAllDevices = false
    #endif
    
    @Published var heartRate: String = "--"
    @Published var isScanning = false
    @Published var statusMessage = "Ready to scan"
    @Published var batteryStatus: String = "Unknown"
    @Published var batteryLevel: Int = -1
    @Published var lastUpdateTime: Date?
    @Published var batteryLastUpdated: Date?
    
    // Service UUIDs
    let batteryServiceCBUUID = CBUUID(string: "180F")  // Standard battery service
    let batteryLevelCharacteristicCBUUID = CBUUID(string: "2A19")  // Standard battery level characteristic
    let heartRateServiceCBUUID = CBUUID(string: "180D")
    let heartRateMeasurementCharacteristicCBUUID = CBUUID(string: "2A37")
    let ouraServiceCBUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") // Oura Ring service UUID
    
    // Known battery service UUIDs for different devices
    let knownBatteryServices: [CBUUID] = [
        CBUUID(string: "180F")  // Standard battery service
    ]
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)

        // Refresh dummy values every 0.5 seconds
        if AppConfig.SCREENSHOT_MODE {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.addDummyValues()
            }
        }
    }

    func addDummyValues() {
        // Add dummy values here
        self.batteryLevel = AppConfig.MockData.batteryLevel
        self.batteryStatus = "\(self.batteryLevel)%"
        self.lastUpdateTime = Date()
        self.batteryLastUpdated = Date()
        statusMessage = "Connected to HRMPro+:893594"
        self.heartRate = "72"  // or any value you want

    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth is powered on"
            startScanning()  // Auto-start scanning when Bluetooth is ready
        case .poweredOff:
            statusMessage = "Bluetooth is powered off"
        case .unauthorized:
            statusMessage = "Bluetooth is not authorized"
        case .unsupported:
            statusMessage = "Bluetooth is not supported"
        default:
            statusMessage = "Unknown state"
        }
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not powered on"
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        
        #if DEBUG
        if debugScanAllDevices {
            // Debug mode: scan for all devices
            centralManager.scanForPeripherals(withServices: nil)
            statusMessage = "Scanning... (Debug: All Devices)"
        } else {
            centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID])
        }
        #else
        // Production mode: only scan for heart rate devices
        centralManager.scanForPeripherals(withServices: [heartRateServiceCBUUID])
        #endif
        
        // Cancel any existing timer when starting a new scan
        scanStopTimer?.invalidate()
        scanStopTimer = nil
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
        scanStopTimer?.invalidate()
        scanStopTimer = nil
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Only add devices that have a name
        guard let name = peripheral.name, !name.isEmpty else { return }
        
        // Check if this is a heart rate device
        let isHeartRateDevice = advertisementData[CBAdvertisementDataServiceUUIDsKey] != nil &&
            (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(heartRateServiceCBUUID) == true
        
        // Check if we already have this device
        if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredDevices.append((peripheral: peripheral, name: name, isHeartRateDevice: isHeartRateDevice))
        }
        
        // If we don't have a connected device yet and this is a heart rate device, connect to it
        if heartRatePeripheral == nil && isHeartRateDevice {
            connectTo(peripheral: peripheral)
        }
    }
    
    func connectTo(peripheral: CBPeripheral) {
        // If we have a current connection, disconnect it first
        if let current = heartRatePeripheral {
            pendingConnection = peripheral
            centralManager.cancelPeripheralConnection(current)
            return
        }
        
        // Otherwise connect directly
        heartRatePeripheral = peripheral
        heartRatePeripheral?.delegate = self
        centralManager.connect(peripheral)
        statusMessage = "Connecting to \(peripheral.name ?? "Unknown Device")..."
        
        // Schedule stopping scan after 60 seconds
        scanStopTimer?.invalidate()
        scanStopTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
            self?.statusMessage = "Scan stopped after 60s of connection"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusMessage = "Connected to \(peripheral.name ?? "Unknown Device")"
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        statusMessage = "Failed to connect to \(peripheral.name ?? "Unknown Device")"
        heartRatePeripheral = nil
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        statusMessage = "Disconnected from \(peripheral.name ?? "Unknown Device")"
        heartRatePeripheral = nil
        batteryStatus = "No device connected"
        
        // If we have a pending connection, connect to it now
        if let pending = pendingConnection {
            pendingConnection = nil
            connectTo(peripheral: pending)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            statusMessage = "Error discovering services: \(error!.localizedDescription)"
            return
        }
        
        print("Device: \(peripheral.name ?? "Unknown")")
        if let services = peripheral.services {
            for service in services {
                print("Found service: \(service)")
            }
        }
        
        // Look for battery service on any connected device
        if let batteryService = peripheral.services?.first(where: { service in
            // Check against known battery service UUIDs
            if knownBatteryServices.contains(service.uuid) {
                return true
            }
            
            // Check for friendly name "Battery"
            if service.uuid.description == "Battery" {
                return true
            }
            
            return false
        }) {
            peripheral.discoverCharacteristics([batteryLevelCharacteristicCBUUID], for: batteryService)
            batteryStatus = "Reading..."
        } else {
            batteryStatus = "No battery info"
        }
        
        // For heart rate devices, also look for heart rate service
        if let heartRateService = peripheral.services?.first(where: { $0.uuid == heartRateServiceCBUUID }) {
            peripheral.discoverCharacteristics([heartRateMeasurementCharacteristicCBUUID], for: heartRateService)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            statusMessage = "Error discovering characteristics: \(error!.localizedDescription)"
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == batteryLevelCharacteristicCBUUID {
                // Enable notifications for battery level
                peripheral.setNotifyValue(true, for: characteristic)
                // Initial read
                peripheral.readValue(for: characteristic)
                // Set up more frequent battery level readings (every 15 seconds)
                Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                    if peripheral.state == .connected {
                        peripheral.readValue(for: characteristic)
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            statusMessage = "Error reading characteristic: \(error!.localizedDescription)"
            return
        }
        
        if characteristic.uuid == batteryLevelCharacteristicCBUUID,
           let batteryData = characteristic.value,
           batteryData.count >= 1 {
            let batteryLevel = batteryData[0]
            batteryStatus = "\(batteryLevel)%"
        }
        
        if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID,
           let heartRateData = characteristic.value {
            var heartRate: UInt16 = 0
            let bytesRead = heartRateData.withUnsafeBytes { bytes in
                if heartRateData[0] & 0x01 == 0 {
                    // First bit is 0, so the heart rate is in the second byte
                    heartRate = UInt16(bytes[1])
                    return 2
                } else {
                    // First bit is 1, so the heart rate is in the second and third bytes
                    heartRate = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
                    return 3
                }
            }
            
            if bytesRead > 0 {
                lastUpdateTime = Date()
                DispatchQueue.main.async {
                    self.heartRate = String(heartRate)
                }
            }
        }
    }
}

struct DebugView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Binding var brightness: Double
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var timeSinceLastUpdate: String {
        guard let lastUpdate = bluetoothManager.lastUpdateTime else {
            return "No data received"
        }
        let timeInterval = Date().timeIntervalSince(lastUpdate)
        return String(format: "%.1f seconds ago", timeInterval)
    }
    
    var batteryText: String {
        if bluetoothManager.batteryLevel >= 0 {
            return "\(bluetoothManager.batteryStatus)"
        } else {
            return bluetoothManager.batteryStatus
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Battery:")
                Text(batteryText)
            }
            
            HStack {
                Text("Last Update:")
                Text(timeSinceLastUpdate)
                    .monospacedDigit()
            }
            .id(currentTime)
            
            Text(bluetoothManager.statusMessage)
                .foregroundColor(.gray)
            
            // Available Devices Section
            if( true ) {    
                if(AppConfig.SCREENSHOT_MODE) {    
                    MockDevicesView()
                }
                else{
                    DevicesView(bluetoothManager: bluetoothManager)
                }
                
            }else{
                if !bluetoothManager.discoveredDevices.isEmpty {
                    Text("Available Devices:")
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(bluetoothManager.discoveredDevices.sorted { device1, device2 in
                                // Sort heart rate devices to the top
                                if device1.isHeartRateDevice && !device2.isHeartRateDevice {
                                    return true
                                }
                                if !device1.isHeartRateDevice && device2.isHeartRateDevice {
                                    return false
                                }
                                // For devices of the same type, sort by name
                                return device1.name < device2.name
                            }, id: \.peripheral.identifier) { device in
                                HStack {
                                    Text(device.name)
                                        .foregroundColor(device.peripheral.identifier == bluetoothManager.heartRatePeripheral?.identifier ? .green : .white)
                                    if device.peripheral.identifier == bluetoothManager.heartRatePeripheral?.identifier {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    if device.isHeartRateDevice {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(.red)
                                    }
                                    Spacer()
                                    if device.peripheral.identifier != bluetoothManager.heartRatePeripheral?.identifier {
                                        Button("Connect") {
                                            bluetoothManager.connectTo(peripheral: device.peripheral)
                                        }
                                        .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(device.isHeartRateDevice ? Color.blue.opacity(0.3) : Color.black.opacity(0.3))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 200)  // Limit height of scroll area
                }
            }
            
            Button(action: {
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                } else {
                    bluetoothManager.startScanning()
                }
            }) {
                HStack {
                    if bluetoothManager.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Scanning")
                    } else {
                        Text("Start Scanning")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(10)
            }
            
            HStack(spacing: 20) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        brightness = max(0.1, brightness - 0.1)
                    }
                }) {
                    HStack {
                        Image(systemName: "sun.min.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.2))
                        Text("Darker")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        brightness = min(1.0, brightness + 0.1)
                    }
                }) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.white)
                        Text("Brighter")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var showControls = true
    @State private var brightness: Double = 1.0
    
    var nightColor: Color {
        let warmColor = Color(red: 1.0, green: 0.3, blue: 0.2)
        return Color.white.interpolateTo(color: warmColor, fraction: 1 - brightness)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    showControls.toggle()
                }) {
                    Image(systemName: showControls ? "moon.fill" : "moon")
                        .font(.title2)
                        .foregroundColor(nightColor)
                        .opacity(brightness)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .offset(x: -4, y: 0)
            }
            
            if showControls {
                DebugView(bluetoothManager: bluetoothManager, brightness: $brightness)
                    .padding(.horizontal)
                    .transition(.opacity)
            }
            
            Spacer()
            
            Text(bluetoothManager.heartRate)
                .font(.system(size: 80, weight: .bold))
                .opacity(brightness)
                .foregroundColor(nightColor)
                .padding()
            
            Spacer()
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(!showControls ? .hidden : .visible)
    }
}

extension Color {
    func interpolateTo(color: Color, fraction: Double) -> Color {
        let fraction = max(0, min(1, fraction))
        
        let color1 = UIColor(self)
        let color2 = UIColor(color)
        
        var red1: CGFloat = 0
        var green1: CGFloat = 0
        var blue1: CGFloat = 0
        var alpha1: CGFloat = 0
        color1.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1)
        
        var red2: CGFloat = 0
        var green2: CGFloat = 0
        var blue2: CGFloat = 0
        var alpha2: CGFloat = 0
        color2.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2)
        
        let red = red1 * (1 - fraction) + red2 * fraction
        let green = green1 * (1 - fraction) + green2 * fraction
        let blue = blue1 * (1 - fraction) + blue2 * fraction
        let alpha = alpha1 * (1 - fraction) + alpha2 * fraction
        
        return Color(uiColor: UIColor(red: red, green: green, blue: blue, alpha: alpha))
    }
}
