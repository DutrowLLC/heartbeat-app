import SwiftUI
import CoreBluetooth

struct DevicesView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        // Available Devices Section
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
        } else {
            Text("No devices found")
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
    }
}

struct MockDevicesView: View {
    // No need for BluetoothManager since we're using static mock data
    
    var body: some View {
        // Available Devices Section
        if !AppConfig.MockData.devices.isEmpty {
            Text("Available Devices:")
                .foregroundColor(.gray)
                .padding(.top, 4)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(AppConfig.MockData.devices.sorted { device1, device2 in
                        // Sort heart rate devices to the top
                        if device1.isHeartRateDevice && !device2.isHeartRateDevice {
                            return true
                        }
                        if !device1.isHeartRateDevice && device2.isHeartRateDevice {
                            return false
                        }
                        // For devices of the same type, sort by name
                        return device1.name < device2.name
                    }, id: \.name) { device in
                        HStack {
                            Text(device.name)
                                .foregroundColor(device.isConnected ? .green : .white)
                            if device.isConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            if device.isHeartRateDevice {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            if !device.isConnected {
                                Button("Connect") {
                                    // Mock connection action
                                    print("Would connect to \(device.name)")
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
        } else {
            Text("No devices found")
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
    }
}