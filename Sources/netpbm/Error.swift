public enum ParseError: Error {
    case wrongFormat // header is wrong
    case ioError
    case internalInconsistency
    case insufficientMemory
    case unexpectedEndOfFile
    case junkWhereBitsShouldBe
    case junkWhereUnsignedIntegerShouldBe
    case tooBigNumber
    case imageTooLarge
    case badPixelValue
}

public enum WriteError: Error {
    case ioError
    case wrongMaxVal
    case insufficientMemory
    case badFormat
    case internalInconsistency
}
