import AppKit
import Foundation

/// Read-only reader for Arrangement section records observed in Logic Pro's saved ProjectData.
/// The .logicx format is undocumented; keep this parser isolated and fail closed when
/// its record framing is not recognized.
enum LogicProjectImporter {
    private struct Record {
        let tag: String
        let headerOffset: Int
        let payload: Range<Int>
    }

    static func importProject(at packageURL: URL) throws -> ImportedLogicProject {
        let dataURL = try projectDataURL(in: packageURL)
        let data = try Data(contentsOf: dataURL, options: .mappedIfSafe)
        let records = try readRecords(from: data)
        let names = readNames(from: data, records: records)
        let sections = readSections(from: data, records: records, names: names)
        let timeSignatures = readTimeSignatures(from: data, records: records)
        let tempoChanges = readTempoChanges(from: data, records: records)

        guard !sections.isEmpty else {
            throw ImportError.noNamedSections
        }
        return ImportedLogicProject(
            projectName: packageURL.deletingPathExtension().lastPathComponent,
            projectURL: packageURL,
            sections: sections,
            timeSignatures: timeSignatures,
            tempoChanges: tempoChanges,
            timecodeFrameRate: readFrameRate(beside: dataURL)
        )
    }

    private static func readFrameRate(beside dataURL: URL) -> Int? {
        let metadataURL = dataURL.deletingLastPathComponent().appendingPathComponent("MetaData.plist")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let index = metadata["FrameRateIndex"] as? Int else { return nil }
        // Support the integral, non-drop SMPTE formats. Other formats need their
        // own timecode conversion before they can be used for reliable locating.
        switch index {
        case 0: return 24
        case 1: return 25
        case 3: return 30
        default: return nil
        }
    }

    static func projectDataURL(in packageURL: URL) throws -> URL {
        let alternativesURL = packageURL.appendingPathComponent("Alternatives", isDirectory: true)
        let alternatives = try FileManager.default.contentsOfDirectory(
            at: alternativesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = alternatives
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("ProjectData") }
        guard let dataURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ImportError.projectDataNotFound
        }
        return dataURL
    }

    private static func readRecords(from data: Data) throws -> [Record] {
        // ProjectData begins with a small file header, followed by framed records.
        var offset = 24
        var records: [Record] = []
        while offset + 36 <= data.count {
            let tagData = data.subdata(in: offset..<(offset + 4))
            guard let tag = String(data: tagData, encoding: .ascii),
                  let payloadLength = data.littleEndianUInt32(at: offset + 28) else {
                break
            }
            let payloadStart = offset + 36
            let payloadEnd = payloadStart + Int(payloadLength)
            guard payloadEnd <= data.count, payloadLength <= 10_000_000 else { break }
            records.append(Record(tag: tag, headerOffset: offset, payload: payloadStart..<payloadEnd))
            offset = payloadEnd
        }
        guard !records.isEmpty else { throw ImportError.unrecognizedProjectData }
        return records
    }

    private static func readNames(from data: Data, records: [Record]) -> [UInt32: String] {
        var names: [UInt32: String] = [:]
        for record in records where record.tag == "qSxT" {
            guard let link = data.littleEndianUInt16(at: record.headerOffset + 10),
                  record.payload.count >= 24,
                  let textOffset = data.littleEndianUInt32(at: record.payload.lowerBound + 16),
                  textOffset >= 24, Int(textOffset) < record.payload.count else { continue }
            // qSxT has a binary prefix; its text-offset field currently points
            // 98 bytes into the payload. New sections may use null-terminated
            // plain text, while older or formatted names contain an RTF document.
            let start = record.payload.lowerBound + Int(textOffset)
            let bytes = Data(data[start..<record.payload.upperBound].prefix { $0 != 0 })
            guard !bytes.isEmpty else { continue }
            let decoded: String?
            if bytes.starts(with: Data("{\\rtf".utf8)) {
                decoded = (try? NSAttributedString(
                    data: bytes,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ))?.string
            } else {
                decoded = String(data: bytes, encoding: .utf8)
                    ?? String(data: bytes, encoding: .windowsCP1252)
            }
            guard let name = decoded?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            names[UInt32(link)] = name
        }
        return names
    }

    private static func readSections(from data: Data, records: [Record], names: [UInt32: String]) -> [ArrangementSection] {
        var sections: [ArrangementSection] = []
        let sequenceRecords = records.enumerated().filter { $0.element.tag == "qSvE" }
        let markerTrackIndices = markerTrackSequenceIndices(in: sequenceRecords, data: data)

        for (recordIndex, record) in sequenceRecords where !markerTrackIndices.contains(recordIndex) {
            var cursor = record.payload.lowerBound
            while cursor + 16 <= record.payload.upperBound {
                guard let eventType = data.littleEndianUInt32(at: cursor) else { break }
                guard data[cursor + 7] & 0x80 == 0, eventType == 0x12 else {
                    cursor += 16
                    continue
                }
                guard cursor + 48 <= record.payload.upperBound,
                      let position = data.littleEndianUInt32(at: cursor + 4),
                      let textSlot = data.littleEndianUInt32(at: cursor + 16),
                      let length = data.littleEndianUInt32(at: cursor + 28),
                      let name = names[textSlot] else {
                    cursor += 48
                    continue
                }
                // Logic's marker event positions include a 40-quarter-note origin offset.
                let tick = Int(position) - 38_400
                if tick >= 0 {
                    sections.append(ArrangementSection(name: name, startTick: tick, lengthTicks: Int(length)))
                }
                cursor += 48
            }
        }
        return sections.sorted {
            if $0.startTick == $1.startTick { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.startTick < $1.startTick
        }
    }

    private static func readTimeSignatures(from data: Data, records: [Record]) -> [TimeSignature] {
        var signatures: [TimeSignature] = []
        for record in records where record.tag == "qSvE" {
            var cursor = record.payload.lowerBound
            while cursor + 16 <= record.payload.upperBound {
                guard let eventType = data.littleEndianUInt32(at: cursor) else { break }
                if data[cursor + 7] & 0x80 == 0,
                   eventType == 0x30,
                   let position = data.littleEndianUInt32(at: cursor + 4) {
                    let denominatorPower = Int(data[cursor + 11])
                    let numerator = Int(data[cursor + 12])
                    if denominatorPower <= 5, numerator > 0 {
                        let denominator = 1 << denominatorPower
                        signatures.append(TimeSignature(
                            startTick: Int(position) - 38_400,
                            numerator: numerator,
                            denominator: denominator
                        ))
                    }
                }
                cursor += 16
            }
        }
        return Dictionary(grouping: signatures, by: \.startTick)
            .compactMap { $0.value.last }
            .sorted { $0.startTick < $1.startTick }
    }

    private static func readTempoChanges(from data: Data, records: [Record]) -> [TempoChange] {
        var changes: [TempoChange] = []
        for record in records where record.tag == "qSvE" {
            guard data.littleEndianUInt32(at: record.payload.lowerBound) == 0x60 else { continue }
            var cursor = record.payload.lowerBound
            while cursor + 32 <= record.payload.upperBound {
                guard data.littleEndianUInt32(at: cursor) == 0x60,
                      let position = data.littleEndianUInt64(at: cursor + 4),
                      let rawTempo = data.littleEndianUInt32(at: cursor + 16) else {
                    cursor += 16
                    continue
                }
                let startTick = Int(position) - 38_400
                let bpm = Double(rawTempo) / 10_000
                if startTick >= 0, bpm > 0, bpm < 1000 {
                    changes.append(TempoChange(startTick: startTick, beatsPerMinute: bpm))
                }
                cursor += 32
            }
        }
        return Dictionary(grouping: changes, by: \.startTick)
            .compactMap { $0.value.last }
            .sorted { $0.startTick < $1.startTick }
    }

    /// Logic stores the ordinary Marker track in the sequence triple immediately
    /// after the sequence whose events are type 0x11. Both that sequence and the
    /// Arrangement section sequence can contain 0x12 events, so exclude the
    /// following triple instead of merging every named 0x12 event in the project.
    private static func markerTrackSequenceIndices(
        in sequences: [(offset: Int, element: Record)],
        data: Data
    ) -> Set<Int> {
        var excluded = Set<Int>()
        for position in sequences.indices {
            let record = sequences[position].element
            guard containsEventType(0x11, in: record, data: data),
                  sequences.indices.contains(position + 1) else { continue }
            excluded.insert(sequences[position + 1].offset)
        }
        return excluded
    }

    private static func containsEventType(_ type: UInt32, in record: Record, data: Data) -> Bool {
        var cursor = record.payload.lowerBound
        while cursor + 16 <= record.payload.upperBound {
            if data[cursor + 7] & 0x80 == 0, data.littleEndianUInt32(at: cursor) == type { return true }
            cursor += 16
        }
        return false
    }

    enum ImportError: LocalizedError {
        case projectDataNotFound
        case unrecognizedProjectData
        case noNamedSections

        var errorDescription: String? {
            switch self {
            case .projectDataNotFound:
                return "Couldn’t find ProjectData inside this Logic project."
            case .unrecognizedProjectData:
                return "This Logic project uses a ProjectData layout CueX doesn’t recognize yet."
            case .noNamedSections:
                return "No linked named section markers were found in the saved project."
            }
        }
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func littleEndianUInt64(at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        var value: UInt64 = 0
        for byteOffset in 0..<8 {
            value |= UInt64(self[offset + byteOffset]) << (byteOffset * 8)
        }
        return value
    }
}
