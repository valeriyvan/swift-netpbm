public enum Bit: Int {
    case zero
    case one
}

extension Bit {
    @inlinable func inverted() -> Bit {
        self == .zero ? .one : .zero
    }
}
