//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
// This file contains parts of from an original project called Blink.
// If you want to know more about Blink, see <http://www.github.com/blinksh/blink>.
//
// Modified by Gentris Leci on 12/17/19.
// Copyright © 2019 Gentris Leci.
//
// This file is part of piPhone
//
// piPhone is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// piPhone is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with piPhone.  If not, see <https://www.gnu.org/licenses/>.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController, WKScriptMessageHandler, PiPhoneDelegate {
    var peripheral: Peripheral?
    private var keyboardIsShown = false
    private var keyboardRect: CGRect?
    private var termView: TermView!
    private var keyboardView: KeyboardView!
    private var coverView: UIView!
    private let termViewScriptName = "interOp"
    private let keyboardViewScriptName = "_kb"
    private var bluetoothManager: BluetoothManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.addKeyboardObservers()
    }
    
    func addKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
        
    @objc func keyboardWillShow(notification: NSNotification) {
        self.keyboardIsShown = true
        if let keyboardRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            self.keyboardRect = keyboardRect
            self.termView.frame = self.termViewFrame()
            self.view.setNeedsLayout()
        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        self.keyboardIsShown = false
        self.keyboardRect = nil
        self.termView.frame = self.termViewFrame()
        self.view.setNeedsLayout()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.loadSubViews()
    }
    
    private func loadSubViews() {
        let configuration = WKWebViewConfiguration()
        configuration.selectionGranularity = .character
        configuration.userContentController.add(self, name: termViewScriptName)
        configuration.userContentController.add(self, name: keyboardViewScriptName)
        
        termView = TermView(frame: termViewFrame(), configuration: configuration)
        keyboardView = KeyboardView(frame: .zero, configuration: configuration)
        coverView = UIView(frame: UIScreen.main.bounds)
        
        coverView.backgroundColor = .black
        
        let interaction = TermGesturesInteraction(jsScrollerPath: "t.scrollPort_.scroller_", keyboardView: keyboardView)
        termView.addInteraction(interaction)
        
        view.addSubview(termView)
        view.addSubview(keyboardView)
        view.addSubview(coverView)
    }
    
    // Delegate functions
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Message.Name: ", message.name)
        if message.name == self.termViewScriptName {
            let payload: NSDictionary = message.body as! NSDictionary
            let operation:String = payload["op"] as! String
            let data = payload["data"] as! NSDictionary
            
            if operation == "terminalReady" {
                let sizeData = data["size"] as! NSDictionary
                self.terminalReady(sizeData)
            } else if operation == "fontSizeChanged" {
                
            } else if operation == "sigwinch" {
                termView.cols = data["cols"] as! Int
                termView.rows = data["rows"] as! Int
                
                let data = "{\"cols\": \(termView.cols), \"rows\": \(termView.rows)}"
                peripheral?.write(data: data, characteristic: peripheral?.screenCharacteristic)
            }
        } else if message.name == self.keyboardViewScriptName {
            let body: NSDictionary = message.body as! NSDictionary
            guard let op: String = body["op"] as? String else {
                return
            }
            
            if (op == "out") {
                let data: String = body["data"] as! String
                peripheral?.write(data: data, characteristic: peripheral?.commandCharacteristic);
                print("kbData: ", data)
            }
        }
    }
    
    func didUpdateBluetoothState(state: CBManagerState) {
        var stateString = ""
        
        if (state == .poweredOff) {
            stateString = "OFF"
        } else if (state == .poweredOn) {
            stateString = "ON"
        } else {
            stateString = "N/A"
        }
            
        let data = "[piPhone] Bluetooth state: \(stateString).\r\n"
        termView.write(data)
    }

    func didConnect() {
        let data = "[piPhone] Connected to peripheral.\r\n"
        termView.write(data)
    }
    
    func didDisconnect() {
        let data = "[piPhone] Disconnected from peripheral.\r\n"
        termView.write(data)
    }
    
    func didFailToConnect() {
        let data = "[piPhone] Failed to connect to peripheral.\r\n"
        termView.write(data)
    }

    func didExecuteCommand(response: Data) {
        let data:String = String(data: response, encoding: String.Encoding.utf8)!
        termView.write(data)
    }
    
    func didUpdateNotificationStateFor(characteristic: CBCharacteristic) {
        if characteristic == peripheral?.screenCharacteristic {
            let data = "{\"cols\": \(termView.cols), \"rows\": \(termView.rows)}"
            peripheral?.write(data: data, characteristic: peripheral?.screenCharacteristic)
        }
    }
    
    func terminalReady(_ data: NSDictionary) {
        UIView.transition(from: coverView, to: termView, duration: 0.3, options: .transitionCrossDissolve) { finished in
            self.coverView.removeFromSuperview()
            self.keyboardView.readyForInput = true
            self.keyboardView.becomeFirstResponder()
            
            self.termView.cols = data["cols"] as! Int
            self.termView.rows = data["rows"] as! Int
            
            self.bluetoothManager = BluetoothManager()
            self.bluetoothManager.piPhoneDelegate = self
        }
    }
    
    func termViewFrame() -> CGRect {
        var inset = view.window?.safeAreaInsets ?? .zero
        
        if let height = self.keyboardRect?.height {
            inset.bottom = max(inset.bottom, height)
        }
        
        return UIScreen.main.bounds.inset(by: inset)
    }
}
