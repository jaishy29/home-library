import SwiftUI
import SwiftData
import PhotosUI

/// Add or edit one book. Edits are kept in local state and only written on Save.
struct BookEditorView: View {
    let book: Book?
    let scannedISBN: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]

    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var year = ""
    @State private var hasBoughtDate = true
    @State private var boughtOn = Date()
    @State private var price = ""
    @State private var boughtFrom = ""
    @State private var status: ReadStatus = .unread
    @State private var finishedOn = Date()
    @State private var loanedTo = ""
    @State private var loanedOn = Date()
    @State private var loanHistory: [LoanRecord] = []
    @State private var notes = ""
    @State private var coverData: Data?

    @State private var lookingUp = false
    @State private var lookupMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var confirmDelete = false
    @State private var loaded = false

    private var isbnNote: (String, Bool)? {
        let d = ISBN.clean(isbn)
        guard !d.isEmpty else { return nil }
        if let n = ISBN.normalize(d) {
            if let dup = allBooks.first(where: { $0.isbn == n && $0 !== book }) {
                return ("You already own this: “\(dup.title)”", true)
            }
            return ("Check digit OK", false)
        }
        return d.count >= 10 ? ("Check digit doesn't match. Re-check the number.", true) : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        coverPicker
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Title", text: $title, axis: .vertical).font(Theme.display(19, .semibold))
                            TextField("Author", text: $author)
                            TextField("Year", text: $year).keyboardType(.numberPad)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("ISBN", text: $isbn).keyboardType(.numberPad).font(.system(.body, design: .monospaced))
                            Button {
                                Task { await lookup() }
                            } label: {
                                if lookingUp { ProgressView() } else { Text("Fill in") }
                            }
                            .disabled(ISBN.normalize(isbn) == nil || lookingUp)
                        }
                        if let note = isbnNote {
                            Text(note.0).font(.caption).foregroundStyle(note.1 ? Theme.loan : Theme.muted)
                        }
                        if let m = lookupMessage {
                            Text(m).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }

                Section("Reading") {
                    Picker("Status", selection: $status) {
                        ForEach(ReadStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if status == .read {
                        DatePicker("Finished on", selection: $finishedOn, displayedComponents: .date)
                    }
                }

                Section("Purchase") {
                    Toggle("I know when I bought it", isOn: $hasBoughtDate)
                    if hasBoughtDate {
                        DatePicker("Bought on", selection: $boughtOn, displayedComponents: .date)
                    }
                    TextField("Price", text: $price).keyboardType(.decimalPad)
                    TextField("Bought from (shop, website, gift…)", text: $boughtFrom)
                }

                Section {
                    TextField("Lent to", text: $loanedTo)
                    if !loanedTo.trimmingCharacters(in: .whitespaces).isEmpty {
                        DatePicker("Lent on", selection: $loanedOn, displayedComponents: .date)
                        if book?.isOnLoan == true {
                            Button("Mark as returned") { markReturned() }
                        }
                    }
                    ForEach(loanHistory.reversed(), id: \.self) { h in
                        Text("\(h.borrower) · \(h.lentOn.formatted(date: .abbreviated, time: .omitted)) → \(h.returnedOn.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                } header: { Text("Loan") } footer: {
                    if !loanHistory.isEmpty { Text("Past loans are listed above.") }
                }

                Section("Notes") {
                    TextField("Anything to remember", text: $notes, axis: .vertical).lineLimit(2...6)
                }

                if book != nil {
                    Section {
                        Button("Delete book", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DotBackground())
            .navigationTitle(book == nil ? "Add a book" : "Edit book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this book from your library? This can't be undone.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete book", role: .destructive) {
                    if let book { context.delete(book) }
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in coverData = image.jpegData(compressionQuality: 0.8) }
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        coverData = img.resized(maxSide: 900).jpegData(compressionQuality: 0.8)
                    }
                }
            }
            .task { await loadInitial() }
        }
        .tint(Theme.accent)
    }

    private var coverPicker: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
            }
            PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose photo", systemImage: "photo") }
            if coverData != nil {
                Button(role: .destructive) { coverData = nil } label: { Label("Remove cover", systemImage: "trash") }
            }
        } label: {
            ZStack {
                if let coverData, let img = UIImage(data: coverData) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Theme.surface2
                    VStack(spacing: 4) {
                        Image(systemName: "camera").font(.title3)
                        Text("Cover").font(.caption2.bold())
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 74, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Cover photo")
    }

    private func loadInitial() async {
        guard !loaded else { return }
        loaded = true
        if let b = book {
            title = b.title; author = b.author; isbn = ISBN.format(b.isbn); year = b.year
            hasBoughtDate = b.boughtOn != nil; boughtOn = b.boughtOn ?? Date()
            price = b.price; boughtFrom = b.boughtFrom
            status = b.status; finishedOn = b.finishedOn ?? Date()
            loanedTo = b.loanedTo; loanedOn = b.loanedOn ?? Date(); loanHistory = b.loanHistory
            notes = b.notes; coverData = b.coverData
        } else if let s = scannedISBN {
            isbn = ISBN.format(s)
            await lookup()
        }
    }

    private func lookup() async {
        guard let n = ISBN.normalize(isbn) else { return }
        lookingUp = true
        lookupMessage = "Looking up \(ISBN.format(n))…"
        defer { lookingUp = false }
        guard let info = await BookLookup.find(isbn: n) else {
            lookupMessage = "Couldn't find this ISBN online. Type the title and author in."
            return
        }
        if title.isEmpty || book == nil { title = info.title }
        if author.isEmpty || book == nil { author = info.author }
        if year.isEmpty { year = info.year }
        if coverData == nil, let c = info.coverData { coverData = UIImage(data: c)?.resized(maxSide: 900).jpegData(compressionQuality: 0.85) ?? c }
        lookupMessage = info.coverData == nil ? "Details filled in. No cover found, so you can add a photo." : "Details and cover filled in. Check them, then save."
    }

    private func markReturned() {
        let who = loanedTo.trimmingCharacters(in: .whitespaces)
        guard !who.isEmpty else { return }
        loanHistory.append(LoanRecord(borrower: who, lentOn: loanedOn, returnedOn: Date()))
        loanedTo = ""
    }

    private func save() {
        let target = book ?? Book()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.author = author.trimmingCharacters(in: .whitespaces)
        target.isbn = ISBN.normalize(isbn) ?? ISBN.clean(isbn)
        target.year = year.trimmingCharacters(in: .whitespaces)
        target.boughtOn = hasBoughtDate ? boughtOn : nil
        target.price = price.trimmingCharacters(in: .whitespaces)
        target.boughtFrom = boughtFrom.trimmingCharacters(in: .whitespaces)
        target.status = status
        target.finishedOn = status == .read ? finishedOn : nil
        let who = loanedTo.trimmingCharacters(in: .whitespaces)
        target.loanedTo = who
        target.loanedOn = who.isEmpty ? nil : loanedOn
        target.loanHistory = loanHistory
        target.notes = notes
        target.coverData = coverData
        if book == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// Wraps the system camera for taking a cover photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img.resized(maxSide: 900)) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
