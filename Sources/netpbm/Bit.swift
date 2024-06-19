public enum Bit: Int {
    case zero = 0
    case one = 1
}

public extension Bit {
    @inlinable func inverted() -> Bit {
        self == .zero ? .one : .zero
    }
}

extension [Bit] {
    func packed() -> [UInt8] {
        var packedBytes = [UInt8]()
        var currentByte: UInt8 = 0
        var bitCount = 0

        for bit in self {
            // Each bit should be either 0 or 1
            let bitValue: UInt8 = bit == .zero ? 0 : 1

            // Shift the bit into the correct position in the current byte
            currentByte |= (bitValue << (7 - bitCount))

            // Move to the next bit position
            bitCount += 1

            // If we have filled a byte, append it to the array and reset
            if bitCount == 8 {
                packedBytes.append(currentByte)
                currentByte = 0
                bitCount = 0
            }
        }

        // If there are leftover bits, append the last byte
        if bitCount > 0 {
            packedBytes.append(currentByte)
        }

        return packedBytes
    }
}
