// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation

/// Augments synthetic dock-swipe CGEvents with the raw IOHID payload
/// required by the Dock server on modern macOS (macOS 15+ / macOS 27)
/// inside CGEvent field 4205.
enum DockSwipeAugmentor {
    private static let rawPayloadFieldID: UInt16 = 4205
    private static let kIOHIDEventTypeVelocity: UInt32 = 9
    private static let kIOHIDEventTypeFluidTouchGesture: UInt32 = 23
    private static let kIOHIDGestureFlavorDockPrimary: UInt16 = 3

    static var requiresAugmentation: Bool {
        if let override = ProcessInfo.processInfo.environment["ISS_FORCE_EVENT_AUGMENTATION"] {
            return override == "1"
        }
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major >= 15
    }

    private struct ParsedField {
        var fieldID: UInt16
        var tag: UInt8
        var sizeWords: UInt16
        var payload: Data
    }

    private static func doubleToFixed1616(_ val: Double) -> Int32 {
        let fixed = Int32(val * 65536.0)
        if fixed == 0 && val != 0.0 {
            return val > 0.0 ? 1 : -1
        }
        return fixed
    }

    private typealias CGEventCreateDataFunction = @convention(c) (CFAllocator?, CGEvent) -> Unmanaged<CFData>?
    private static let cgEventCreateDataFn: CGEventCreateDataFunction? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventCreateData") else { return nil }
        return unsafeBitCast(sym, to: CGEventCreateDataFunction.self)
    }()

    private static func generateIOHIDPayload(for event: CGEvent) -> Data {
        let phase = event.getIntegerValueField(CGEventField(rawValue: 132)!)
        let motion = event.getIntegerValueField(CGEventField(rawValue: 123)!)
        let progress = event.getDoubleValueField(CGEventField(rawValue: 124)!)
        let posX = event.getDoubleValueField(CGEventField(rawValue: 125)!)
        let posY = event.getDoubleValueField(CGEventField(rawValue: 126)!)
        let velX = event.getDoubleValueField(CGEventField(rawValue: 129)!)
        let velY = event.getDoubleValueField(CGEventField(rawValue: 130)!)
        let swipeMask = event.getIntegerValueField(CGEventField(rawValue: 115)!)

        let includeVelocity = (velX != 0.0 || velY != 0.0 || phase == 4)
        let eventCount: UInt32 = includeVelocity ? 2 : 1

        var data = Data()

        // 1. IOHIDSystemQueueElementHeader (28 bytes)
        var timestamp = UInt64(event.timestamp)
        if timestamp == 0 {
            timestamp = mach_absolute_time()
        }
        var senderID: UInt64 = 0
        var options: UInt32 = 0
        var attrLen: UInt32 = 0
        var count = eventCount

        data.append(Data(bytes: &timestamp, count: 8))
        data.append(Data(bytes: &senderID, count: 8))
        data.append(Data(bytes: &options, count: 4))
        data.append(Data(bytes: &attrLen, count: 4))
        data.append(Data(bytes: &count, count: 4))

        // 2. IOHIDFluidTouchGestureData (40 bytes)
        // Base (16 bytes)
        var fluidSize: UInt32 = 40
        var fluidType = kIOHIDEventTypeFluidTouchGesture
        var fluidOptions = UInt32((UInt32(phase) & 0xFF) << 24)
        let fluidDepth: UInt8 = 0
        var reserved: (UInt8, UInt8, UInt8) = (0, 0, 0)

        data.append(Data(bytes: &fluidSize, count: 4))
        data.append(Data(bytes: &fluidType, count: 4))
        data.append(Data(bytes: &fluidOptions, count: 4))
        data.append(fluidDepth)
        data.append(Data(bytes: &reserved, count: 3))

        // Fluid fields
        var fixedPosX = doubleToFixed1616(posX)
        var fixedPosY = doubleToFixed1616(posY)
        var fixedPosZ: Int32 = 0
        var mask = UInt32(swipeMask)
        var gMotion = UInt16(motion)
        var gFlavor = kIOHIDGestureFlavorDockPrimary
        var fixedProgress = doubleToFixed1616(progress)

        data.append(Data(bytes: &fixedPosX, count: 4))
        data.append(Data(bytes: &fixedPosY, count: 4))
        data.append(Data(bytes: &fixedPosZ, count: 4))
        data.append(Data(bytes: &mask, count: 4))
        data.append(Data(bytes: &gMotion, count: 2))
        data.append(Data(bytes: &gFlavor, count: 2))
        data.append(Data(bytes: &fixedProgress, count: 4))

        // 3. Optional IOHIDVelocityEventData (28 bytes)
        if includeVelocity {
            var velSize: UInt32 = 28
            var velType = kIOHIDEventTypeVelocity
            var velOptions: UInt32 = 0
            let velDepth: UInt8 = 1
            var velReserved: (UInt8, UInt8, UInt8) = (0, 0, 0)

            data.append(Data(bytes: &velSize, count: 4))
            data.append(Data(bytes: &velType, count: 4))
            data.append(Data(bytes: &velOptions, count: 4))
            data.append(velDepth)
            data.append(Data(bytes: &velReserved, count: 3))

            var fixedVelX = doubleToFixed1616(velX)
            var fixedVelY = doubleToFixed1616(velY)
            var fixedVelZ: Int32 = 0

            data.append(Data(bytes: &fixedVelX, count: 4))
            data.append(Data(bytes: &fixedVelY, count: 4))
            data.append(Data(bytes: &fixedVelZ, count: 4))
        }

        return data
    }

    static func augment(event: CGEvent) -> CGEvent? {
        guard let createData = cgEventCreateDataFn,
              let originalCFData = createData(nil, event)?.takeRetainedValue() else {
            return nil
        }
        let originalData = originalCFData as Data
        guard originalData.count >= 4 else { return nil }

        // Read version
        let version = originalData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
        guard version == 2 else { return nil }

        var fields: [ParsedField] = []
        var offset = 4

        while offset + 4 <= originalData.count {
            let sizeWords = originalData.withUnsafeBytes {
                $0.load(fromByteOffset: offset, as: UInt16.self).bigEndian
            }
            let tagAndField = originalData.withUnsafeBytes {
                $0.load(fromByteOffset: offset + 2, as: UInt16.self).bigEndian
            }
            offset += 4

            let tag = UInt8((tagAndField >> 14) & 0x3)
            let fieldID = tagAndField & 0x3FFF

            let payloadLength: Int
            switch tag {
            case 0: // int64 or binary blob
                payloadLength = (sizeWords == 1) ? 8 : Int(sizeWords)
            case 1, 3: // int32 or float
                payloadLength = Int(sizeWords) * 4
            default:
                return nil
            }

            guard offset + payloadLength <= originalData.count else { return nil }
            let payload = originalData.subdata(in: offset..<(offset + payloadLength))
            fields.append(ParsedField(fieldID: fieldID, tag: tag, sizeWords: sizeWords, payload: payload))
            offset += payloadLength
        }

        // Generate IOHID payload
        let newPayload = generateIOHIDPayload(for: event)
        let newPayloadWords = UInt16(newPayload.count)

        // Serialize back
        var output = Data()
        var versionBE = UInt32(2).bigEndian
        output.append(Data(bytes: &versionBE, count: 4))

        var added4205 = false
        for field in fields {
            if field.fieldID == rawPayloadFieldID {
                var sizeWordsBE = newPayloadWords.bigEndian
                var tagAndFieldBE = ((UInt16(0) << 14) | rawPayloadFieldID).bigEndian
                output.append(Data(bytes: &sizeWordsBE, count: 2))
                output.append(Data(bytes: &tagAndFieldBE, count: 2))
                output.append(newPayload)
                added4205 = true
            } else {
                var sizeWordsBE = field.sizeWords.bigEndian
                var tagAndFieldBE = ((UInt16(field.tag) << 14) | field.fieldID).bigEndian
                output.append(Data(bytes: &sizeWordsBE, count: 2))
                output.append(Data(bytes: &tagAndFieldBE, count: 2))
                output.append(field.payload)
            }
        }

        if !added4205 {
            var sizeWordsBE = newPayloadWords.bigEndian
            var tagAndFieldBE = ((UInt16(0) << 14) | rawPayloadFieldID).bigEndian
            output.append(Data(bytes: &sizeWordsBE, count: 2))
            output.append(Data(bytes: &tagAndFieldBE, count: 2))
            output.append(newPayload)
        }

        return CGEvent(withDataAllocator: nil, data: output as CFData)
    }
}
