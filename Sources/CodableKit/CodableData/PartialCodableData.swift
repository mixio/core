
/// Reference wrapper for `PostgreSQLData` being mutated
/// by the PostgreSQL data coders.
final class PartialCodableData {
    /// The partial data.
    var data: CodableData

    /// Creates a new `PartialPostgreSQLData`.
    init(data: CodableData) {
        self.data = data
    }

    /// Sets the `PostgreSQLData` at supplied coding path.
    func set(_ data: CodableData, at path: [CodingKey]) {
        guard path.count == 1 else {
            fatalError()
        }
        set(&self.data, to: data, at: path)
    }

    /// Returns the value, if one at from the given path.
    func get(at path: [CodingKey]) -> CodableData? {
        var child = data
        for seg in path {
            switch child {
            case .array(let arr):
                guard let index = seg.intValue, arr.count > index else {
                    return nil
                }
                child = arr[index]
            case .dictionary(let dict):
                guard let value = dict[seg.stringValue] else {
                    return nil
                }
                child = value
            default:
                return nil
            }
        }
        return child
    }

    /// Sets the mutable `PostgreSQLData` to supplied data at coding path.
    private func set(_ context: inout CodableData, to value: CodableData, at path: [CodingKey]) {
        guard path.count >= 1 else {
            context = value
            return
        }

        let end = path[0]

        var child: CodableData?
        switch path.count {
        case 1:
            child = value
        case 2...:
            if let index = end.intValue {
                let array = context.array ?? []
                if array.count > index {
                    child = array[index]
                } else {
                    child = CodableData.array([])
                }
                set(&child!, to: value, at: Array(path[1...]))
            } else {
                child = context.dictionary?[end.stringValue] ?? CodableData.dictionary([:])
                set(&child!, to: value, at: Array(path[1...]))
            }
        default: break
        }

        if let index = end.intValue {
            if case .array(var arr) = context {
                if arr.count > index {
                    arr[index] = child ?? .null
                } else {
                    arr.append(child ?? .null)
                }
                context = .array(arr)
            } else if let child = child {
                context = .array([child])
            }
        } else {
            if case .dictionary(var dict) = context {
                dict[end.stringValue] = child
                context = .dictionary(dict)
            } else if let child = child {
                context = .dictionary([
                    end.stringValue: child
                    ])
            }
        }
    }
}

/// MARK: Decoding

extension PartialCodableData {
    /// Gets a `nil` from the supplied path or throws a decoding error.
    func decodeNil(at path: [CodingKey]) -> Bool {
        if let value = get(at: path) {
            return value == .null
        } else {
            return true
        }
    }

    /// Gets a `Bool` from the supplied path or throws a decoding error.
    func decodeBool(at path: [CodingKey]) throws -> Bool {
        switch try requireGet(Bool.self, at: path) {
        case .bool(let value): return value
        case .decoder(let decoder): return try Bool(from: decoder)
        default: throw DecodingError.typeMismatch(Bool.self, .init(codingPath: path, debugDescription: ""))
        }
    }

    /// Gets a `String` from the supplied path or throws a decoding error.
    func decodeString(at path: [CodingKey]) throws -> String {
        switch try requireGet(String.self, at: path) {
        case .string(let value): return value
        case .decoder(let decoder): return try String(from: decoder)
        default: throw DecodingError.typeMismatch(String.self, .init(codingPath: path, debugDescription: ""))
        }
    }


    /// Gets a `String` from the supplied path or throws a decoding error.
    func decode<D>(_ type: D.Type = D.self, at path: [CodingKey]) throws -> D where D: Decodable {
        if let value = get(at: path), case .decoder(let decoder) = value {
            let single = try decoder.singleValueContainer()
            return try single.decode(D.self)
        } else {
            let decoder = _CodableDataDecoder(partialData: self, at: path)
            return try D(from: decoder)
        }
    }

    /// Gets a `Float` from the supplied path or throws a decoding error.
    func decodeFixedWidthInteger<I>(_ type: I.Type = I.self, at path: [CodingKey]) throws -> I
        where I: FixedWidthInteger, I: Decodable
    {
        switch try requireGet(I.self, at: path) {
        case .int(let value): return try safeCast(value, at: path)
        case .int8(let value): return try safeCast(value, at: path)
        case .int16(let value): return try safeCast(value, at: path)
        case .int32(let value): return try safeCast(value, at: path)
        case .int64(let value): return try safeCast(value, at: path)
        case .uint(let value): return try safeCast(value, at: path)
        case .uint8(let value): return try safeCast(value, at: path)
        case .uint16(let value): return try safeCast(value, at: path)
        case .uint32(let value): return try safeCast(value, at: path)
        case .uint64(let value): return try safeCast(value, at: path)
        case .decoder(let decoder): return try I(from: decoder)
        default: throw DecodingError.typeMismatch(type, .init(codingPath: path, debugDescription: ""))
        }
    }

    /// Gets a `FloatingPoint` from the supplied path or throws a decoding error.
    func decodeFloatingPoint<F>(_ type: F.Type = F.self, at path: [CodingKey]) throws -> F
        where F: BinaryFloatingPoint, F: Decodable
    {
        switch try requireGet(F.self, at: path) {
        case .int(let value): return F(value)
        case .int8(let value): return F(value)
        case .int16(let value): return F(value)
        case .int32(let value): return F(value)
        case .int64(let value): return F(value)
        case .uint(let value): return F(value)
        case .uint8(let value): return F(value)
        case .uint16(let value): return F(value)
        case .uint32(let value): return F(value)
        case .uint64(let value): return F(value)
        case .float(let float): return F(float)
        case .double(let double): return F(double)
        case .decoder(let decoder): return try F(from: decoder)
        default: throw DecodingError.typeMismatch(F.self, .init(codingPath: path, debugDescription: ""))
        }
    }

    /// Gets a value at the supplied path or throws a decoding error.
    func requireGet<T>(_ type: T.Type, at path: [CodingKey]) throws -> CodableData {
        switch get(at: path) {
        case .some(let w): return w
        case .none: throw DecodingError.valueNotFound(T.self, .init(codingPath: path, debugDescription: ""))
        }
    }

    /// Safely casts one `FixedWidthInteger` to another.
    private func safeCast<I, V>(_ value: V, at path: [CodingKey], to type: I.Type = I.self) throws -> I where V: FixedWidthInteger, I: FixedWidthInteger {
        if let existing = value as? I {
            return existing
        }

        guard I.bitWidth >= V.bitWidth else {
            throw DecodingError.typeMismatch(type, .init(codingPath: path, debugDescription: "Bit width too wide: \(I.bitWidth) < \(V.bitWidth)"))
        }
        guard value <= I.max else {
            throw DecodingError.typeMismatch(type, .init(codingPath: path, debugDescription: "Value too large: \(value) > \(I.max)"))
        }
        guard value >= I.min else {
            throw DecodingError.typeMismatch(type, .init(codingPath: path, debugDescription: "Value too small: \(value) < \(I.min)"))
        }
        return I(value)
    }
}
