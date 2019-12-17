//
//  BluetoothManager.swift
//  piPhone
//
//  Created by Gentris Leci on 12/17/19.
//  Copyright © 2019 Gentris Leci. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol PiPhoneDelegate {
    func didConnect()
    func didDisconnect()
    func didFailToConnect()
    func didExecuteCommand(response: String)
}

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var piPhoneDelegate: PiPhoneDelegate?
    
    private var centralManager:CBCentralManager?
    private var pi:CBPeripheral?
    private var scanTimer:Timer?
    private var pauseTimer:Timer?
    
    private let serviceUUID = CBUUID(string: "50315dc8-bd51-4561-a9ec-eac52609b17a")
    private let characteristicUUID = CBUUID(string: "e6b8f004-b286-4826-b6ca-cba2eb628c03")
    private let peripheralName = "pi"
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func initScanTimer() -> Timer {
        return Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(startScanning), userInfo: nil, repeats: true)
    }
    
    private func initPauseTimer() -> Timer {
        return Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(stopScanning), userInfo: nil, repeats: true)
    }
    
    @objc private func startScanning() {
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: nil)
        if pauseTimer == nil {
            pauseTimer = initPauseTimer()
        }
    }
    
    @objc private func stopScanning() {
        centralManager?.stopScan()
        if scanTimer == nil {
            scanTimer = initScanTimer()
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != CBManagerState.poweredOn {
            print("Bluetooth is not ready for communication.")
            return
        }
        
        print("Bluetooth is ON and ready for communication.")
        
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String else {
            return;
        }
        
        if name == peripheralName {
            pi = peripheral
            pi?.delegate = self
            
            scanTimer?.invalidate()
            pauseTimer?.invalidate()

            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Couldn't connect to the peripheral.")
        
        if central.state != CBManagerState.poweredOn {
            print("Bluetooth is not ready for communication.")
            return
        }
        
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        piPhoneDelegate?.didConnect()
        print("Successfully connected to the peripheral.")
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Peripheral got disconnected.")
        startScanning()
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error while discovering services: \(error.localizedDescription)")
            return;
        }
        
        guard let services = peripheral.services else {
            print("No services discovered.")
            return
        }
        
        print("Services discovered.")
        
        for service in services {
            print("Service with UUID: \(service.uuid)")
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error while discovering characteristics: \(error.localizedDescription)")
            return;
        }
        
        guard let characteristics = service.characteristics else {
            print("No characteristics discovered.")
            return
        }
        
        print("Characteristics discovered.")

        for characteristic in characteristics {
            print("Characteristic with UUID: \(characteristic.uuid)")
            pi?.setNotifyValue(true, for: characteristic)
            
            if characteristic.uuid == characteristicUUID {
                let initialString:Data? = "echo \"$(whoami)@$(hostname):/../ $\"".data(using: String.Encoding.utf8)
                pi?.writeValue(initialString!, for: characteristic, type: CBCharacteristicWriteType.withResponse)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if !characteristic.isNotifying {
            pi?.setNotifyValue(true, for: characteristic)
        }
    }
        
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error while updating the characteristic's value: \(error.localizedDescription)")
            return
        }
        
        if let value = characteristic.value {
            let readableValue:String = String(data: value, encoding: String.Encoding.utf8)!
            print("Pi output: \(readableValue)")
        }
    }
}