//
//  AudioDeviceManager.swift
//  VoiceTranslation
//
//  管理音频输入设备的选择和切换
//

import Foundation
import AVFoundation
import CoreAudio

@MainActor
class AudioDeviceManager: ObservableObject {
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var currentInputDevice: AudioDevice?
    
    // 记录用户手动选择的设备
    private var userSelectedDeviceUID: String?
    
    struct AudioDevice: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let uid: String
        let isDefault: Bool
        let manufacturer: String?
        
        var displayName: String {
            if isDefault {
                return "\(name) (默认)"
            }
            return name
        }
    }
    
    init() {
        refreshDevices()
        setupNotifications()
    }
    
    func refreshDevices() {
        availableInputDevices = getInputDevices()
        
        // 过滤掉虚拟音频设备和有问题的设备
        let filteredDevices = availableInputDevices.filter { device in
            // 排除已知的虚拟设备
            let virtualDevices = ["Microsoft Teams Audio", "WeMeet Audio Device", "ZoomAudioDevice"]
            let isVirtual = virtualDevices.contains { device.name.contains($0) }
            
            if isVirtual {
                print("⚠️ 跳过虚拟音频设备: \(device.name)")
                return false
            }
            return true
        }
        
        // 如果用户之前手动选择了设备，优先使用
        if let userSelectedUID = userSelectedDeviceUID,
           let userDevice = filteredDevices.first(where: { $0.uid == userSelectedUID }) {
            print("🎯 恢复用户选择的设备: \(userDevice.name)")
            currentInputDevice = userDevice
            setAudioInputDevice(userDevice)
            return
        }
        
        // 如果当前有设备且仍然可用，保持不变
        if let current = currentInputDevice,
           filteredDevices.contains(where: { $0.uid == current.uid }) {
            print("📌 保持当前设备: \(current.name)")
            return
        }
        
        // Respect the microphone already chosen in System Settings. Recreating a view/service
        // must not switch a deliberately selected built-in/USB microphone back to AirPods.
        if let defaultDevice = filteredDevices.first(where: { $0.isDefault }) {
            currentInputDevice = defaultDevice
            return
        }

        // 只在没有当前设备时自动选择
        // 优先选择顺序：
        // 1. AirPods (用户常用的无线耳机)
        // 2. USB 音频设备 (如 Logi)
        // 3. MacBook Pro 麦克风（当输出为内置扬声器时）
        // 4. 其他默认设备
        
        if let airpods = filteredDevices.first(where: { 
            $0.name.contains("AirPods") 
        }) {
            print("🎧 发现 AirPods: \(airpods.name)")
            currentInputDevice = airpods
            setAudioInputDevice(airpods)
        } else if let logiDevice = filteredDevices.first(where: { 
            $0.name.contains("Logi") || $0.name.contains("H340") || $0.name.contains("USB")
        }) {
            print("🎧 自动选择 USB 音频设备: \(logiDevice.name)")
            currentInputDevice = logiDevice
            setAudioInputDevice(logiDevice)
        } else if let macbookMic = filteredDevices.first(where: { 
            $0.name.contains("MacBook") && $0.name.contains("麦克风")
        }) {
            // 检查当前输出设备是否为 MacBook Pro 扬声器
            if isOutputDeviceMacBookSpeaker() {
                print("🎤 选择 MacBook Pro 麦克风（输出为内置扬声器）")
                currentInputDevice = macbookMic
                setAudioInputDevice(macbookMic)
            } else {
                print("⚠️ MacBook Pro 麦克风需要输出设备为内置扬声器才能正常工作")
                // 尝试切换输出设备
                if setOutputToMacBookSpeaker() {
                    currentInputDevice = macbookMic
                    setAudioInputDevice(macbookMic)
                }
            }
        } else if let defaultDevice = filteredDevices.first(where: { $0.isDefault }) {
            print("📱 使用默认设备: \(defaultDevice.name)")
            currentInputDevice = defaultDevice
        }
        
        // 更新可用设备列表供 UI 显示
        availableInputDevices = filteredDevices
    }
    
    private func getInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        
        // 获取所有音频设备
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 获取设备列表大小
        AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &propertySize
        )
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var audioDevices = [AudioObjectID](repeating: 0, count: deviceCount)
        
        // 获取设备列表
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &propertySize,
            &audioDevices
        )
        
        // 获取默认输入设备ID
        var defaultInputID: AudioObjectID = 0
        var defaultSize: UInt32 = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0, nil,
            &defaultSize,
            &defaultInputID
        )
        
        // 遍历每个设备
        for deviceID in audioDevices {
            // 检查是否为输入设备
            var inputChannelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var bufferListSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(
                deviceID,
                &inputChannelAddress,
                0, nil,
                &bufferListSize
            )
            
            if bufferListSize > 0 {
                // 这是一个输入设备
                let name = getDeviceProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
                let uid = getDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
                let manufacturer = getDeviceProperty(deviceID: deviceID, selector: kAudioObjectPropertyManufacturer)
                
                let device = AudioDevice(
                    id: deviceID,
                    name: name,
                    uid: uid,
                    isDefault: deviceID == defaultInputID,
                    manufacturer: manufacturer.isEmpty ? nil : manufacturer
                )
                
                devices.append(device)
                print("📎 发现输入设备: \(device.displayName) [UID: \(device.uid)]")
            }
        }
        
        return devices
    }
    
    private func getDeviceProperty(deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 首先获取属性大小
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &propertySize
        )
        
        guard status == noErr && propertySize > 0 else {
            return ""
        }
        
        // 根据属性类型处理
        if selector == kAudioObjectPropertyName || selector == kAudioDevicePropertyDeviceNameCFString {
            // 使用CFString获取设备名称
            var deviceName: CFString = "" as CFString
            propertySize = UInt32(MemoryLayout<CFString>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &propertySize,
                &deviceName
            )
            
            if status == noErr {
                return deviceName as String
            }
        } else if selector == kAudioDevicePropertyDeviceUID {
            // UID使用CFString
            var deviceUID: CFString = "" as CFString
            propertySize = UInt32(MemoryLayout<CFString>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &propertySize,
                &deviceUID
            )
            
            if status == noErr {
                return deviceUID as String
            }
        } else if selector == kAudioObjectPropertyManufacturer {
            // 制造商使用UInt32（FourCharCode）
            var manufacturer: UInt32 = 0
            propertySize = UInt32(MemoryLayout<UInt32>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &propertySize,
                &manufacturer
            )
            
            if status == noErr {
                // 将FourCharCode转换为字符串
                let bytes = [
                    UInt8((manufacturer >> 24) & 0xFF),
                    UInt8((manufacturer >> 16) & 0xFF),
                    UInt8((manufacturer >> 8) & 0xFF),
                    UInt8(manufacturer & 0xFF)
                ]
                return String(bytes: bytes, encoding: .macOSRoman) ?? ""
            }
        }
        
        return ""
    }
    
    func selectDevice(_ device: AudioDevice) {
        print("👤 用户手动选择设备: \(device.name)")
        userSelectedDeviceUID = device.uid
        currentInputDevice = device
        setAudioInputDevice(device)
    }
    
    private func setAudioInputDevice(_ device: AudioDevice) {
        // 设置为系统默认输入设备
        var deviceID = device.id
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        )
        
        if status == noErr {
            print("✅ 已设置音频输入设备: \(device.name)")
        } else {
            print("❌ 设置音频输入设备失败: \(status)")
        }
    }
    
    private func setupNotifications() {
        // 在macOS上监听音频设备变化
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 设置音频设备变化监听器
        let listenerProc: AudioObjectPropertyListenerProc = { _, _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("AudioDevicesChanged"), object: nil)
            }
            return noErr
        }
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            listenerProc,
            nil
        )
        
        // 监听设备变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: Notification.Name("AudioDevicesChanged"),
            object: nil
        )
    }
    
    @objc private func handleDeviceChange() {
        Task { @MainActor in
            refreshDevices()
        }
    }
    
    // MARK: - Output Device Management
    
    /// 检查当前输出设备是否为 MacBook 扬声器
    private func isOutputDeviceMacBookSpeaker() -> Bool {
        var defaultOutputID: AudioObjectID = 0
        var propertySize: UInt32 = UInt32(MemoryLayout<AudioObjectID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &propertySize,
            &defaultOutputID
        )
        
        guard status == noErr else { return false }
        
        // 获取输出设备名称
        let outputName = getDeviceProperty(deviceID: defaultOutputID, selector: kAudioObjectPropertyName)
        print("🔊 当前输出设备: \(outputName)")
        
        return outputName.contains("MacBook") && (outputName.contains("扬声器") || outputName.contains("Speaker"))
    }
    
    /// 设置输出设备为 MacBook 扬声器
    private func setOutputToMacBookSpeaker() -> Bool {
        // 获取所有输出设备
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &propertySize
        )
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var audioDevices = [AudioObjectID](repeating: 0, count: deviceCount)
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &propertySize,
            &audioDevices
        )
        
        // 查找 MacBook 扬声器
        for deviceID in audioDevices {
            // 检查是否为输出设备
            var outputChannelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var bufferListSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(
                deviceID,
                &outputChannelAddress,
                0, nil,
                &bufferListSize
            )
            
            if bufferListSize > 0 {
                let name = getDeviceProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
                if name.contains("MacBook") && (name.contains("扬声器") || name.contains("Speaker")) {
                    // 设置为默认输出设备
                    var outputAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    
                    var outputID = deviceID
                    let status = AudioObjectSetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &outputAddress,
                        0, nil,
                        UInt32(MemoryLayout<AudioObjectID>.size),
                        &outputID
                    )
                    
                    if status == noErr {
                        print("✅ 已切换输出设备到: \(name)")
                        return true
                    }
                }
            }
        }
        
        print("❌ 未找到 MacBook 扬声器")
        return false
    }
    
    /// 获取当前音频会话配置信息（用于调试）
    func getAudioSessionInfo() -> String {
        var info = "音频设备信息:\n"
        
        // 输入设备
        info += "\n输入设备:\n"
        for device in availableInputDevices {
            let current = device == currentInputDevice ? " ✓" : ""
            info += "  - \(device.displayName)\(current)\n"
        }
        
        // 输出设备状态
        info += "\n输出设备:\n"
        if isOutputDeviceMacBookSpeaker() {
            info += "  - MacBook 扬声器 ✓\n"
        } else {
            info += "  - 其他设备\n"
        }
        
        return info
    }
}
