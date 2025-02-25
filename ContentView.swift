import SwiftUI
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    @Published var heartRatePeripheral: CBPeripheral?
    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String)] = []
    
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
    let heartRateServiceCBUUID = CBUUID(string: "0x180D")
    let ouraServiceCBUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") // Oura Ring service UUID
    let heartRateMeasurementCharacteristicCBUUID = CBUUID(string: "0x2A37")
    let batteryServiceCBUUID = CBUUID(string: "180F")
    let batteryLevelCharacteristicCBUUID = CBUUID(string: "2A19")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth is powered on"
        case .poweredOff:
            statusMessage = "Bluetooth is powered off"
        case .unauthorized:
            statusMessage = "Bluetooth permission denied"
        default:
            statusMessage = "Bluetooth is not available"
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
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Scan stopped"
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown Device"
        if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredDevices.append((peripheral: peripheral, name: name))
        }
        
        // If we don't have a connected device yet, connect to this one
        if heartRatePeripheral == nil {
            connectTo(peripheral: peripheral)
        }
    }
    
    func connectTo(peripheral: CBPeripheral) {
        // Disconnect current device if any
        if let current = heartRatePeripheral {
            centralManager.cancelPeripheralConnection(current)
        }
        
        heartRatePeripheral = peripheral
        heartRatePeripheral?.delegate = self
        centralManager.connect(peripheral)
        statusMessage = "Connecting to \(peripheral.name ?? "Unknown Device")..."
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusMessage = "Connected to HRM"
        peripheral.discoverServices([heartRateServiceCBUUID, batteryServiceCBUUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            statusMessage = "Error discovering services: \(error!.localizedDescription)"
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics([heartRateMeasurementCharacteristicCBUUID, batteryLevelCharacteristicCBUUID], for: service)
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
        
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == heartRateMeasurementCharacteristicCBUUID {
            let firstByte = data[0]
            let isUint16 = ((firstByte & 0x01) == 0x01)
            
            var hrValue: UInt16
            if isUint16 {
                hrValue = UInt16(data[1]) + (UInt16(data[2]) << 8)
            } else {
                hrValue = UInt16(data[1])
            }
            
            DispatchQueue.main.async {
                self.heartRate = String(hrValue)
                self.lastUpdateTime = Date()
            }
        } else if characteristic.uuid == batteryLevelCharacteristicCBUUID {
            let rawValue = data[0]
            let level = Int(rawValue)
            
            // Convert numeric level to status description
            let status: String
            if level >= 75 {
                status = "Good"
            } else if level >= 25 {
                status = "OK"
            } else if level >= 10 {
                status = "Low"
            } else {
                status = "Critical"
            }
            
            DispatchQueue.main.async {
                self.batteryStatus = status
                self.batteryLevel = level
                self.batteryLastUpdated = Date()
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
            return "\(bluetoothManager.batteryStatus) (\(bluetoothManager.batteryLevel)%)"
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
            if !bluetoothManager.discoveredDevices.isEmpty {
                Text("Available Devices:")
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(bluetoothManager.discoveredDevices, id: \.peripheral.identifier) { device in
                            HStack {
                                Text(device.name)
                                    .foregroundColor(device.peripheral.identifier == bluetoothManager.heartRatePeripheral?.identifier ? .green : .white)
                                if device.peripheral.identifier == bluetoothManager.heartRatePeripheral?.identifier {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
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
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 200)  // Limit height of scroll area
            }
            
            Button(action: {
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                } else {
                    bluetoothManager.startScanning()
                }
            }) {
                Text(bluetoothManager.isScanning ? "Stop Scanning" : "Start Scanning")
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
