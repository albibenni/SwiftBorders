import Foundation

func warn(_ message: String) {
    FileHandle.standardError.write(Data("swiftborders: \(message)\n".utf8))
}

func info(_ message: String) {
    print("swiftborders: \(message)")
}
