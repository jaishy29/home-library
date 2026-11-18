import Foundation
import SwiftData

enum ReadStatus: String, Codable, CaseIterable, Identifiable {
    case unread, reading, read
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unread: return "To be read"
        case .reading: return "Reading"
        case .read: return "Read"
        }
    }
}

struct LoanRecord: Codable, Hashable {
    var borrower: String
    var lentOn: Date
    var returnedOn: Date
}

@Model
final class Book {
    var title: String = ""
    var author: String = ""
    var isbn: String = ""
    var year: String = ""
    var boughtOn: Date?
    var price: String = ""
    var boughtFrom: String = ""
    var statusRaw: String = ReadStatus.unread.rawValue
    var finishedOn: Date?
    var loanedTo: String = ""
    var loanedOn: Date?
    var loanHistory: [LoanRecord] = []
    var notes: String = ""
    @Attribute(.externalStorage) var coverData: Data?
    var addedAt: Date = Date()

    init(title: String = "", author: String = "", isbn: String = "") {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.boughtOn = Date()
        self.addedAt = Date()
    }

    var status: ReadStatus {
        get { ReadStatus(rawValue: statusRaw) ?? .unread }
        set { statusRaw = newValue.rawValue }
    }

    var isOnLoan: Bool { !loanedTo.trimmingCharacters(in: .whitespaces).isEmpty }

    var daysOnLoan: Int {
        guard let d = loanedOn else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0)
    }
}
