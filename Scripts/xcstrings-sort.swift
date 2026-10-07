#!/usr/bin/env swift
//
// Sort the keys of a string catalog into the order Xcode writes them.
//
//   swift Scripts/xcstrings-sort.swift Sources/Shared/Resources/Localizable.xcstrings
//   swift Scripts/xcstrings-sort.swift Sources/Shared/Resources/Localizable.xcstrings --check
//
// Why this exists: Xcode rewrites the whole catalog whenever it extracts strings, and it
// writes the keys in sorted order. Keys spliced in at a convenient neighbour instead of at
// their sorted position therefore buy a five-figure cosmetic diff on the next Xcode build.
// Measured on 2026-09-21 against Sodalite's catalog: 216 of 1224 keys sat out of
// order and carried ~34k lines, which is the ~23k/23k diff that kept reappearing.
//
// The order is Foundation's localizedStandardCompare (case-insensitive, numeric, locale
// aware), not a byte sort. Verified offline against Sodalite e8966e3f, the commit that
// adopted Xcode's own formatting: this comparator reproduces all 958 keys of that file
// exactly, and does so identically under en_US, de_DE and the current locale.
//
// The tool MOVES text blocks, it never reserialises. No serializer round-trips this file
// (see the xcstrings skill in Sodalite, where this tool comes from), so every byte outside
// the block order stays untouched, and the run aborts unless the blocks before and after are
// the same multiset, the line count is unchanged, and both versions parse to equal JSON.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("xcstrings-sort: " + message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: xcstrings-sort.swift <catalog.xcstrings> [--check]") }
let path = args[1]
let checkOnly = args.contains("--check")

guard let original = try? String(contentsOfFile: path, encoding: .utf8) else {
    fail("cannot read \(path)")
}

// The "strings" object holds one block per key. Locate its braces.
let opener = "\n  \"strings\" : {\n"
guard let openerRange = original.range(of: opener) else {
    fail("no top level \"strings\" object in \(path)")
}
let innerStart = original.index(before: openerRange.upperBound) // the newline after the brace

/// Scans forward from `index` (on a `{`) to the matching `}`, skipping over string literals.
func matchingBrace(from index: String.Index, in text: String) -> String.Index? {
    var depth = 0
    var inString = false
    var escaped = false
    var i = index
    while i < text.endIndex {
        let c = text[i]
        if escaped {
            escaped = false
        } else if inString {
            if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "\"" {
            inString = true
        } else if c == "{" {
            depth += 1
        } else if c == "}" {
            depth -= 1
            if depth == 0 { return i }
        }
        i = text.index(after: i)
    }
    return nil
}

// The opener ends with "{\n"; step back two characters to land on the brace itself.
let stringsBrace = original.index(openerRange.upperBound, offsetBy: -2)
guard original[stringsBrace] == "{", let stringsEnd = matchingBrace(from: stringsBrace, in: original) else {
    fail("cannot find the end of the \"strings\" object")
}

let prefix = String(original[original.startIndex..<original.index(after: innerStart)])
let suffix = String(original[stringsEnd...])
let body = original[original.index(after: innerStart)..<stringsEnd]

/// Reads the JSON string literal starting at `index` (on its opening quote).
func readStringLiteral(from index: String.Index, in text: String) -> (value: String, end: String.Index)? {
    var i = text.index(after: index)
    var raw = "\""
    var escaped = false
    while i < text.endIndex {
        let c = text[i]
        raw.append(c)
        if escaped {
            escaped = false
        } else if c == "\\" {
            escaped = true
        } else if c == "\"" {
            guard let data = raw.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
            else { return nil }
            return (value, i)
        }
        i = text.index(after: i)
    }
    return nil
}

// `body` is a slice of `original`, so their indices are interchangeable.
var blocks: [(key: String, text: String)] = []
var cursor = body.startIndex
var lastBlockEnd = body.startIndex
while cursor < body.endIndex {
    // Skip the separators between blocks.
    while cursor < body.endIndex, body[cursor] == "\n" || body[cursor] == " " || body[cursor] == "," {
        cursor = original.index(after: cursor)
    }
    guard cursor < body.endIndex else { break }
    guard body[cursor] == "\"", let literal = readStringLiteral(from: cursor, in: original) else {
        fail("unexpected character where a key was expected")
    }
    guard let valueBrace = original[literal.end...].firstIndex(of: "{"),
          let valueEnd = matchingBrace(from: valueBrace, in: original)
    else { fail("key \(literal.value) has no object value") }
    blocks.append((literal.value, String(original[cursor...valueEnd])))
    cursor = original.index(after: valueEnd)
    lastBlockEnd = cursor
}

// Whatever sits between the last block and the closing brace (a newline and the object's own
// indent) belongs to the body and has to survive the reorder.
let tail = String(original[lastBlockEnd..<stringsEnd])

guard !blocks.isEmpty else { fail("no keys found") }

let sortedKeys = blocks.map(\.key).sorted {
    $0.compare($1, options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering],
               range: nil, locale: Locale(identifier: "en_US")) == .orderedAscending
}

if blocks.map(\.key) == sortedKeys {
    print("xcstrings-sort: \(path) is already in Xcode's key order (\(blocks.count) keys)")
    exit(0)
}

let outOfPlace = zip(blocks.map(\.key), sortedKeys).filter { $0 != $1 }.count
if checkOnly {
    fail("\(path) is not in Xcode's key order (\(outOfPlace) of \(blocks.count) positions differ). "
         + "Run: swift Scripts/xcstrings-sort.swift \(path)")
}

let byKey = Dictionary(blocks.map { ($0.key, $0.text) }, uniquingKeysWith: { a, _ in a })
let reordered = sortedKeys.map { "    " + byKey[$0]! }.joined(separator: ",\n")
let rebuilt = prefix + reordered + tail + suffix

// Gates. Anything unexpected here means the block scan was wrong, so write nothing.
guard rebuilt.split(separator: "\n", omittingEmptySubsequences: false).count
        == original.split(separator: "\n", omittingEmptySubsequences: false).count else {
    fail("line count changed, refusing to write")
}
guard Set(blocks.map(\.text)).count == blocks.count,
      blocks.map(\.text).sorted() == sortedKeys.map({ byKey[$0]! }).sorted() else {
    fail("the set of key blocks changed, refusing to write")
}
guard let before = try? JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary,
      let after = try? JSONSerialization.jsonObject(with: Data(rebuilt.utf8)) as? NSDictionary,
      before.isEqual(after) else {
    fail("the rebuilt catalog is not semantically equal, refusing to write")
}

try! rebuilt.write(toFile: path, atomically: true, encoding: .utf8)
print("xcstrings-sort: sorted \(blocks.count) keys in \(path) (\(outOfPlace) positions differed)")
