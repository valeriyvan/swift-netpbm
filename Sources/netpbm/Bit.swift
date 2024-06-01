public enum Bit: Int {
    case zero
    case one
}

public extension Bit {
    @inlinable func inverted() -> Bit {
        self == .zero ? .one : .zero
    }
}
