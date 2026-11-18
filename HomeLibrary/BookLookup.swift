import Foundation

struct BookInfo {
    var title: String = ""
    var author: String = ""
    var year: String = ""
    var coverData: Data?
}

/// Looks up a book by ISBN in Open Library, falling back to Google Books.
enum BookLookup {
    static func find(isbn: String) async -> BookInfo? {
        if let info = await openLibrary(isbn), !info.title.isEmpty {
            var result = info
            if result.coverData == nil, let g = await googleBooks(isbn) { result.coverData = g.coverData }
            return result
        }
        return await googleBooks(isbn)
    }

    private static func getJSON(_ url: URL) async -> [String: Any]? {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("HomeLibrary-iOS/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    static func download(_ urlString: String?) async -> Data? {
        guard var s = urlString else { return nil }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        guard let url = URL(string: s),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              data.count > 1500 // tiny images are "no cover" placeholders
        else { return nil }
        return data
    }

    private static func openLibrary(_ isbn: String) async -> BookInfo? {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"),
              let root = await getJSON(url),
              let book = root["ISBN:\(isbn)"] as? [String: Any]
        else { return nil }
        var info = BookInfo()
        info.title = book["title"] as? String ?? ""
        if let sub = book["subtitle"] as? String, !sub.isEmpty, info.title.count < 40 { info.title += ": " + sub }
        let authors = (book["authors"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        info.author = authors.joined(separator: ", ")
        if let date = book["publish_date"] as? String, let r = date.range(of: #"\d{4}"#, options: .regularExpression) {
            info.year = String(date[r])
        }
        let cover = book["cover"] as? [String: Any]
        info.coverData = await download(cover?["large"] as? String ?? cover?["medium"] as? String)
        if info.coverData == nil {
            info.coverData = await download("https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false")
        }
        return info
    }

    private static func googleBooks(_ isbn: String) async -> BookInfo? {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"),
              let root = await getJSON(url),
              let items = root["items"] as? [[String: Any]],
              let vol = items.first?["volumeInfo"] as? [String: Any]
        else { return nil }
        var info = BookInfo()
        info.title = vol["title"] as? String ?? ""
        info.author = (vol["authors"] as? [String] ?? []).joined(separator: ", ")
        info.year = String((vol["publishedDate"] as? String ?? "").prefix(4))
        let links = vol["imageLinks"] as? [String: Any]
        if var thumb = links?["thumbnail"] as? String {
            thumb = thumb.replacingOccurrences(of: "&edge=curl", with: "").replacingOccurrences(of: "zoom=1", with: "zoom=2")
            info.coverData = await download(thumb)
        }
        return info
    }
}
