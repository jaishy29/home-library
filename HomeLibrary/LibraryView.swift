import SwiftUI
import SwiftData

enum ShelfFilter: String, CaseIterable {
    case all, read, toRead, loan
}

enum SortOrder: String, CaseIterable, Identifiable {
    case added = "Recently added", title = "Title", author = "Author", bought = "Purchase date"
    var id: String { rawValue }
}

/// Identifies what the editor sheet is showing.
enum EditorTarget: Identifiable {
    case new(isbn: String?)
    case existing(Book)
    var id: String {
        switch self {
        case .new(let isbn): return "new-\(isbn ?? "")"
        case .existing(let b): return "\(b.persistentModelID.hashValue)"
        }
    }
}

struct LibraryView: View {
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @State private var filter: ShelfFilter = .all
    @State private var search = ""
    @State private var sort: SortOrder = .added
    @State private var showScanner = false
    @State private var editor: EditorTarget?

    private var shown: [Book] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let qDigits = ISBN.clean(q)
        let filtered = books.filter { b in
            switch filter {
            case .all: break
            case .read: if b.status != .read { return false }
            case .toRead: if b.status == .read { return false }
            case .loan: if !b.isOnLoan { return false }
            }
            guard !q.isEmpty else { return true }
            return [b.title, b.author, b.loanedTo, b.boughtFrom].contains { $0.lowercased().contains(q) }
                || (!qDigits.isEmpty && b.isbn.contains(qDigits))
        }
        switch sort {
        case .added: return filtered
        case .title: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author: return filtered.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .bought: return filtered.sorted { ($0.boughtOn ?? .distantPast) > ($1.boughtOn ?? .distantPast) }
        }
    }

    private var boughtThisYear: Int {
        let y = Calendar.current.component(.year, from: Date())
        return books.filter { $0.boughtOn.map { Calendar.current.component(.year, from: $0) == y } ?? false }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    stats
                    controls
                    shelf
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
            .background(DotBackground())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) { actionBar }
            .sheet(isPresented: $showScanner) {
                ScannerView { isbn in
                    showScanner = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editor = .new(isbn: isbn) }
                }
            }
            .sheet(item: $editor) { target in
                switch target {
                case .new(let isbn): BookEditorView(book: nil, scannedISBN: isbn)
                case .existing(let b): BookEditorView(book: b, scannedISBN: nil)
                }
            }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 14) {
            BookStackLogo()
            VStack(alignment: .leading, spacing: 4) {
                Text("Home Library").font(Theme.display(32)).foregroundStyle(Theme.accent)
                Text(books.isEmpty
                     ? "Every book on your shelves, read or waiting, home or lent out."
                     : "\(books.count) books · \(boughtThisYear) bought this year · \(books.filter(\.isOnLoan).count) lent out")
                    .font(.footnote).foregroundStyle(Theme.muted)
                Text("EX LIBRIS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.5)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .rotationEffect(.degrees(-2))
            }
        }
        .padding(.top, 12)
    }

    private var stats: some View {
        let read = books.filter { $0.status == .read }.count
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard(.all, books.count, "Owned", Theme.accent)
            statCard(.read, read, "Read", Theme.read)
            statCard(.toRead, books.count - read, "To be read", Theme.accent)
            statCard(.loan, books.filter(\.isOnLoan).count, "Lent out", Theme.loan)
        }
    }

    private func statCard(_ f: ShelfFilter, _ n: Int, _ label: String, _ color: Color) -> some View {
        Button {
            withAnimation(.snappy) { filter = (filter == f && f != .all) ? .all : f }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n)").font(Theme.display(28, .semibold)).foregroundStyle(color).monospacedDigit()
                Text(label.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(filter == f ? Theme.accent : Theme.line, lineWidth: filter == f ? 2.5 : 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == f ? .isSelected : [])
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Title, author, ISBN, borrower", text: $search)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1.5))
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .padding(11)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1.5))
            }
            .accessibilityLabel("Sort books")
        }
    }

    @ViewBuilder private var shelf: some View {
        if books.isEmpty {
            emptyState(title: "Your shelves are waiting",
                       message: "Tap Scan a book and point your camera at the barcode on the back cover. The title, author and cover fill in on their own.")
        } else if shown.isEmpty {
            emptyState(title: "No books on this shelf yet", message: "Try another filter or search.")
        } else {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.persistentModelID) { i, book in
                        if i > 0 { Divider().overlay(Theme.line) }
                        Button { editor = .existing(book) } label: { BookRow(book: book) }
                            .buttonStyle(.plain)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1.5))
                // the shelf plank
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.shelf)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.shelfEdge).frame(height: 3) }
                    .frame(height: 12)
                    .padding(.horizontal, -6)
                    .padding(.top, 2)
                Text("♡ \(shown.count) \(shown.count == 1 ? "book" : "books") on this shelf ♡")
                    .font(Theme.display(13, .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 10)
            }
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "book.pages").font(.system(size: 50)).foregroundStyle(Theme.accent)
            Text(title).font(Theme.display(22, .semibold)).foregroundStyle(Theme.accent)
            Text(message).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1.5))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button { showScanner = true } label: {
                Label("Scan a book", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(PinkButtonStyle())
            Button { editor = .new(isbn: nil) } label: { Text("Add by hand") }
                .buttonStyle(PinkButtonStyle(filled: false))
        }
        .padding(6)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.18), radius: 14, y: 6)
        .padding(.bottom, 10)
    }
}

struct BookRow: View {
    let book: Book
    var body: some View {
        HStack(spacing: 12) {
            CoverView(book: book)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title.isEmpty ? "Untitled" : book.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                Text([book.author.isEmpty ? "Unknown author" : book.author, book.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                HStack(spacing: 6) {
                    StatusPill(status: book.status)
                    if book.isOnLoan {
                        Pill(text: "Lent to \(book.loanedTo) · \(book.daysOnLoan)d", fg: Theme.loan, bg: Theme.loanBg)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
