import Foundation
import Compression

/// 极简 XLSX 读写：ZIP(store/deflate) + SpreadsheetML。
/// 只用 Foundation + Compression，无第三方依赖。
enum XLSX {

    // MARK: - 表结构

    struct Sheet {
        var name: String
        var rows: [[String]]
    }

    // MARK: - 生成

    static func build(_ sheets: [Sheet]) -> Data {
        var files: [(String, Data)] = []

        func xml(_ s: String) -> Data { Data(s.utf8) }

        // [Content_Types].xml
        var ct = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        ct += #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
        ct += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
        ct += #"<Default Extension="xml" ContentType="application/xml"/>"#
        ct += #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
        for i in sheets.indices {
            ct += #"<Override PartName="/xl/worksheets/sheet\#(i + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        ct += "</Types>"
        files.append(("[Content_Types].xml", xml(ct)))

        // _rels/.rels
        var rels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        rels += #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        rels += #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>"#
        rels += "</Relationships>"
        files.append(("_rels/.rels", xml(rels)))

        // xl/workbook.xml
        var wb = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        wb += #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>"#
        for (i, s) in sheets.enumerated() {
            wb += #"<sheet name="\#(esc(s.name))" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
        }
        wb += "</sheets></workbook>"
        files.append(("xl/workbook.xml", xml(wb)))

        // xl/_rels/workbook.xml.rels
        var wbr = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        wbr += #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for i in sheets.indices {
            wbr += #"<Relationship Id="rId\#(i + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(i + 1).xml"/>"#
        }
        wbr += "</Relationships>"
        files.append(("xl/_rels/workbook.xml.rels", xml(wbr)))

        // 各 sheet
        for (i, s) in sheets.enumerated() {
            var sx = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
            sx += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
            for (r, row) in s.rows.enumerated() {
                sx += #"<row r="\#(r + 1)">"#
                for (c, val) in row.enumerated() where !val.isEmpty {
                    let ref = colName(c) + String(r + 1)
                    sx += #"<c r="\#(ref)" t="inlineStr"><is><t xml:space="preserve">\#(esc(val))</t></is></c>"#
                }
                sx += "</row>"
            }
            sx += "</sheetData></worksheet>"
            files.append(("xl/worksheets/sheet\(i + 1).xml", xml(sx)))
        }

        return zip(files)
    }

    // MARK: - 解析

    /// 返回按 workbook 声明顺序排列的表。无法识别则返回空数组。
    static func parse(_ data: Data) -> [Sheet] {
        guard let entries = unzip(data) else { return [] }

        var names: [String] = []
        if let wbData = entries["xl/workbook.xml"],
           let wb = String(data: wbData, encoding: .utf8) {
            names = matches(in: wb, pattern: #"<sheet[^>]*name="([^"]*)""#).map { unesc($0) }
        }

        var shared: [String] = []
        if let ssData = entries["xl/sharedStrings.xml"],
           let ss = String(data: ssData, encoding: .utf8) {
            let d = SharedStringsDelegate()
            let p = XMLParser(data: Data(ss.utf8)); p.delegate = d; p.parse()
            shared = d.strings
        }

        let sheetKeys = entries.keys
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { a, b in sheetIndex(a) < sheetIndex(b) }

        var out: [Sheet] = []
        for (i, key) in sheetKeys.enumerated() {
            guard let d = entries[key] else { continue }
            let del = SheetDelegate(shared: shared)
            let p = XMLParser(data: d); p.delegate = del; p.parse()
            let name = i < names.count ? names[i] : "Sheet\(i + 1)"
            out.append(Sheet(name: name, rows: del.rows))
        }
        return out
    }

    private static func sheetIndex(_ key: String) -> Int {
        let s = key.replacingOccurrences(of: "xl/worksheets/sheet", with: "")
            .replacingOccurrences(of: ".xml", with: "")
        return Int(s) ?? 0
    }

    // MARK: - XML 工具

    static func esc(_ s: String) -> String {
        var o = s
        o = o.replacingOccurrences(of: "&", with: "&amp;")
        o = o.replacingOccurrences(of: "<", with: "&lt;")
        o = o.replacingOccurrences(of: ">", with: "&gt;")
        o = o.replacingOccurrences(of: "\"", with: "&quot;")
        o = o.replacingOccurrences(of: "'", with: "&apos;")
        return o
    }

    static func unesc(_ s: String) -> String {
        var o = s
        o = o.replacingOccurrences(of: "&lt;", with: "<")
        o = o.replacingOccurrences(of: "&gt;", with: ">")
        o = o.replacingOccurrences(of: "&quot;", with: "\"")
        o = o.replacingOccurrences(of: "&apos;", with: "'")
        o = o.replacingOccurrences(of: "&amp;", with: "&")
        return o
    }

    /// 列序号 → A/B/…/Z/AA
    static func colName(_ i: Int) -> String {
        var n = i, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    static func colIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return max(0, n - 1)
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }
}

// MARK: - 单元格解析

private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var buf = ""
    private var inSI = false

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName q: String?, attributes a: [String: String]) {
        if e == "si" { inSI = true; buf = "" }
        if e == "t", inSI { buf = "" }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inSI { buf += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        if e == "si" { strings.append(buf); inSI = false }
    }
}

private final class SheetDelegate: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []
    private var row: [String] = []
    private var cellCol = 0
    private var cellType = ""
    private var buf = ""
    private var inValue = false

    init(shared: [String]) { self.shared = shared }

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName q: String?, attributes a: [String: String]) {
        switch e {
        case "row":
            row = []
        case "c":
            cellCol = a["r"].map { XLSX.colIndex($0) } ?? row.count
            cellType = a["t"] ?? ""
            buf = ""
        case "v", "t":
            inValue = true; buf = ""
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { if inValue { buf += s } }

    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        switch e {
        case "v", "t":
            inValue = false
        case "c":
            var val = buf
            if cellType == "s", let i = Int(val), i < shared.count { val = shared[i] }
            while row.count < cellCol { row.append("") }
            if row.count == cellCol { row.append(val) } else { row[cellCol] = val }
            buf = ""
        case "row":
            rows.append(row)
        default: break
        }
    }
}
