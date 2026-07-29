import SwiftUI
import AppKit

/// Regex-driven syntax highlighting for fenced code blocks.
///
/// Deliberately lightweight: no embedded JavaScript engine, no per-language
/// grammar files. Rules are applied highest-priority first and each character
/// is claimed at most once, so a keyword inside a string stays a string.
enum SyntaxHighlighter {

    /// Semantic token classes, mapped to system colours so both appearances work.
    enum Token {
        case comment
        case string
        case number
        case keyword
        case type
        case plain

        var color: Color {
            switch self {
            case .comment: Color(nsColor: .systemGray)
            case .string: Color(nsColor: .systemRed)
            case .number: Color(nsColor: .systemOrange)
            case .keyword: Color(nsColor: .systemPink)
            case .type: Color(nsColor: .systemTeal)
            case .plain: Color.primary
            }
        }
    }

    /// Highlights `source`, falling back to plain text for unknown languages.
    static func highlight(_ source: String, language: String?) -> AttributedString {
        var attributed = AttributedString(source)
        attributed.foregroundColor = Token.plain.color

        guard let grammar = Grammar.forLanguage(language) else { return attributed }

        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        var claimed = IndexSet()

        for rule in grammar.rules {
            guard let expression = rule.expression else { continue }
            expression.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                let range = rule.captureGroup.map { match.range(at: $0) } ?? match.range
                guard range.location != NSNotFound, range.length > 0 else { return }

                let candidate = IndexSet(integersIn: range.location..<(range.location + range.length))
                guard claimed.intersection(candidate).isEmpty else { return }
                claimed.formUnion(candidate)

                if let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].foregroundColor = rule.token.color
                }
            }
        }

        return attributed
    }

    /// Display name for the language chip above a code block.
    static func displayName(for language: String?) -> String {
        guard let language, !language.isEmpty else { return "text" }
        return Grammar.canonicalName(for: language) ?? language.lowercased()
    }

    // MARK: - Grammars

    private struct Rule {
        let pattern: String
        let token: Token
        /// When set, only this capture group is coloured.
        var captureGroup: Int?
        var options: NSRegularExpression.Options = []

        var expression: NSRegularExpression? {
            try? NSRegularExpression(pattern: pattern, options: options)
        }
    }

    private struct Grammar {
        let rules: [Rule]

        /// Rule order is significant: comments and strings must claim their
        /// characters before keyword and number rules get a look.
        static func make(
            lineComment: [String],
            blockComment: (open: String, close: String)?,
            stringPatterns: [String],
            keywords: [String],
            types: [String]
        ) -> Grammar {
            var rules: [Rule] = []

            if let blockComment {
                let open = NSRegularExpression.escapedPattern(for: blockComment.open)
                let close = NSRegularExpression.escapedPattern(for: blockComment.close)
                rules.append(Rule(
                    pattern: "\(open)[\\s\\S]*?\(close)",
                    token: .comment
                ))
            }

            for marker in lineComment {
                let escaped = NSRegularExpression.escapedPattern(for: marker)
                rules.append(Rule(pattern: "\(escaped).*", token: .comment))
            }

            for pattern in stringPatterns {
                rules.append(Rule(pattern: pattern, token: .string))
            }

            if !keywords.isEmpty {
                rules.append(Rule(
                    pattern: "\\b(?:\(keywords.joined(separator: "|")))\\b",
                    token: .keyword
                ))
            }

            if !types.isEmpty {
                rules.append(Rule(
                    pattern: "\\b(?:\(types.joined(separator: "|")))\\b",
                    token: .type
                ))
            }

            rules.append(Rule(
                pattern: "\\b\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b",
                token: .number
            ))

            return Grammar(rules: rules)
        }

        static func canonicalName(for language: String) -> String? {
            aliases[language.lowercased()]
        }

        static func forLanguage(_ language: String?) -> Grammar? {
            guard let language, let canonical = aliases[language.lowercased()] else { return nil }
            return grammars[canonical]
        }

        private static let doubleQuoted = "\"(?:\\\\.|[^\"\\\\])*\""
        private static let singleQuoted = "'(?:\\\\.|[^'\\\\])*'"
        private static let backtickQuoted = "`(?:\\\\.|[^`\\\\])*`"

        private static let aliases: [String: String] = [
            "swift": "swift",
            "objective-c": "c", "objc": "c", "c": "c", "h": "c",
            "c++": "c", "cpp": "c", "cc": "c", "hpp": "c",
            "csharp": "c", "cs": "c",
            "java": "java", "kotlin": "java", "kt": "java", "scala": "java",
            "javascript": "javascript", "js": "javascript", "jsx": "javascript",
            "typescript": "javascript", "ts": "javascript", "tsx": "javascript",
            "python": "python", "py": "python",
            "ruby": "ruby", "rb": "ruby",
            "go": "go", "golang": "go",
            "rust": "rust", "rs": "rust",
            "php": "php",
            "bash": "shell", "sh": "shell", "zsh": "shell", "shell": "shell",
            "console": "shell", "terminal": "shell",
            "json": "json",
            "yaml": "yaml", "yml": "yaml",
            "sql": "sql",
            "html": "markup", "xml": "markup", "svg": "markup",
            "css": "css", "scss": "css", "sass": "css"
        ]

        private static let grammars: [String: Grammar] = [
            "swift": make(
                lineComment: ["//"],
                blockComment: ("/*", "*/"),
                stringPatterns: ["\"\"\"[\\s\\S]*?\"\"\"", doubleQuoted],
                keywords: [
                    "actor", "any", "as", "associatedtype", "async", "await", "break", "case",
                    "catch", "class", "continue", "default", "defer", "deinit", "do", "else",
                    "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for",
                    "func", "guard", "if", "import", "in", "init", "inout", "internal", "is",
                    "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator",
                    "override", "private", "protocol", "public", "repeat", "required", "return",
                    "self", "some", "static", "struct", "subscript", "super", "switch",
                    "throw", "throws", "true", "try", "typealias", "var", "weak", "where",
                    "while", "unowned"
                ],
                types: [
                    "Any", "AnyObject", "Array", "Bool", "Character", "Data", "Date", "Dictionary",
                    "Double", "Error", "Float", "Int", "Never", "Optional", "Result", "Set",
                    "String", "Task", "UInt", "URL", "Void"
                ]
            ),
            "c": make(
                lineComment: ["//"],
                blockComment: ("/*", "*/"),
                stringPatterns: [doubleQuoted, singleQuoted],
                keywords: [
                    "auto", "break", "case", "catch", "char", "class", "const", "constexpr",
                    "continue", "default", "delete", "do", "double", "else", "enum", "extern",
                    "false", "float", "for", "goto", "if", "inline", "int", "long", "namespace",
                    "new", "nullptr", "operator", "private", "protected", "public", "return",
                    "short", "signed", "sizeof", "static", "struct", "switch", "template",
                    "this", "throw", "true", "try", "typedef", "typename", "union", "unsigned",
                    "using", "virtual", "void", "volatile", "while", "var", "async", "await"
                ],
                types: ["bool", "size_t", "string", "uint8_t", "uint32_t", "uint64_t", "vector"]
            ),
            "java": make(
                lineComment: ["//"],
                blockComment: ("/*", "*/"),
                stringPatterns: ["\"\"\"[\\s\\S]*?\"\"\"", doubleQuoted, singleQuoted],
                keywords: [
                    "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
                    "class", "const", "continue", "data", "default", "do", "double", "else",
                    "enum", "extends", "false", "final", "finally", "float", "for", "fun", "if",
                    "implements", "import", "instanceof", "int", "interface", "long", "native",
                    "new", "null", "object", "package", "private", "protected", "public",
                    "return", "short", "static", "super", "switch", "synchronized", "this",
                    "throw", "throws", "transient", "true", "try", "val", "var", "void",
                    "volatile", "when", "while"
                ],
                types: ["Boolean", "Double", "Integer", "List", "Long", "Map", "Object", "Set", "String"]
            ),
            "javascript": make(
                lineComment: ["//"],
                blockComment: ("/*", "*/"),
                stringPatterns: [doubleQuoted, singleQuoted, backtickQuoted],
                keywords: [
                    "as", "async", "await", "break", "case", "catch", "class", "const",
                    "continue", "debugger", "default", "delete", "do", "else", "enum", "export",
                    "extends", "false", "finally", "for", "from", "function", "get", "if",
                    "implements", "import", "in", "instanceof", "interface", "let", "new",
                    "null", "of", "private", "protected", "public", "readonly", "return", "set",
                    "static", "super", "switch", "this", "throw", "true", "try", "type",
                    "typeof", "undefined", "var", "void", "while", "yield"
                ],
                types: [
                    "Array", "Boolean", "Date", "Error", "Map", "Number", "Object", "Promise",
                    "RegExp", "Set", "String", "Symbol", "any", "boolean", "never", "number",
                    "string", "unknown"
                ]
            ),
            "python": make(
                lineComment: ["#"],
                blockComment: nil,
                stringPatterns: [
                    "\"\"\"[\\s\\S]*?\"\"\"", "'''[\\s\\S]*?'''", doubleQuoted, singleQuoted
                ],
                keywords: [
                    "and", "as", "assert", "async", "await", "break", "class", "continue",
                    "def", "del", "elif", "else", "except", "False", "finally", "for", "from",
                    "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
                    "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"
                ],
                types: [
                    "bool", "bytes", "dict", "float", "frozenset", "int", "list", "object",
                    "set", "str", "tuple"
                ]
            ),
            "ruby": make(
                lineComment: ["#"],
                blockComment: nil,
                stringPatterns: [doubleQuoted, singleQuoted],
                keywords: [
                    "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
                    "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module",
                    "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self",
                    "super", "then", "true", "unless", "until", "when", "while", "yield"
                ],
                types: ["Array", "Hash", "Integer", "Object", "String", "Symbol"]
            ),
            "go": make(
                lineComment: ["//"],
                blockComment: ("/*", "*/"),
                stringPatterns: [doubleQuoted, backtickQuoted, singleQuoted],
                keywords: [
                    "break", "case", "chan", "const", "continue", "default", "defer", "else",
                    "fallthrough", "false", "for", "func", "go", "goto", "if", "import",
                    "interface", "map", "nil", "package", "range", "return", "select", "struct",
                    "switch", "true", "type", "var"
                ],
                types: [
                    "bool", "byte", "error", "float32", "float64", "int", "int32", "int64",
                    "rune", "string", "uint", "uint8", "uint64"
                ]
            ),
            "rust": make(
                lineComment: ["//"],
                blockComment: ("/*", "*/"),
                stringPatterns: [doubleQuoted, singleQuoted],
                keywords: [
                    "as", "async", "await", "break", "const", "continue", "crate", "dyn",
                    "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let",
                    "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
                    "static", "struct", "super", "trait", "true", "type", "unsafe", "use",
                    "where", "while"
                ],
                types: [
                    "Box", "HashMap", "Option", "Result", "String", "Vec", "bool", "char",
                    "f64", "i32", "i64", "str", "u8", "u32", "u64", "usize"
                ]
            ),
            "php": make(
                lineComment: ["//", "#"],
                blockComment: ("/*", "*/"),
                stringPatterns: [doubleQuoted, singleQuoted],
                keywords: [
                    "abstract", "array", "as", "break", "case", "catch", "class", "const",
                    "continue", "declare", "default", "do", "echo", "else", "elseif", "enum",
                    "extends", "false", "final", "finally", "fn", "for", "foreach", "function",
                    "global", "if", "implements", "include", "instanceof", "interface", "match",
                    "namespace", "new", "null", "print", "private", "protected", "public",
                    "readonly", "require", "return", "static", "switch", "throw", "trait",
                    "true", "try", "use", "var", "while", "yield"
                ],
                types: ["bool", "float", "int", "iterable", "mixed", "object", "string", "void"]
            ),
            "shell": make(
                lineComment: ["#"],
                blockComment: nil,
                stringPatterns: [doubleQuoted, singleQuoted],
                keywords: [
                    "case", "cd", "do", "done", "echo", "elif", "else", "esac", "exit",
                    "export", "fi", "for", "function", "if", "in", "local", "return", "set",
                    "source", "then", "unset", "until", "while"
                ],
                types: []
            ),
            "json": make(
                lineComment: [],
                blockComment: nil,
                stringPatterns: [doubleQuoted],
                keywords: ["true", "false", "null"],
                types: []
            ),
            "yaml": make(
                lineComment: ["#"],
                blockComment: nil,
                stringPatterns: [doubleQuoted, singleQuoted],
                keywords: ["false", "no", "null", "true", "yes"],
                types: []
            ),
            "sql": Grammar(rules: [
                Rule(pattern: "--.*", token: .comment),
                Rule(pattern: "/\\*[\\s\\S]*?\\*/", token: .comment),
                Rule(pattern: singleQuoted, token: .string),
                Rule(
                    pattern: "\\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|INDEX|VIEW|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|AS|AND|OR|NOT|NULL|IS|IN|EXISTS|DISTINCT|UNION|ALL|CASE|WHEN|THEN|ELSE|END|WITH|PRIMARY|KEY|FOREIGN|REFERENCES|DEFAULT|CONSTRAINT)\\b",
                    token: .keyword,
                    options: [.caseInsensitive]
                ),
                Rule(pattern: "\\b\\d+(?:\\.\\d+)?\\b", token: .number)
            ]),
            "markup": Grammar(rules: [
                Rule(pattern: "<!--[\\s\\S]*?-->", token: .comment),
                Rule(pattern: "</?([A-Za-z][\\w:-]*)", token: .keyword, captureGroup: 1),
                Rule(pattern: doubleQuoted, token: .string),
                Rule(pattern: singleQuoted, token: .string),
                Rule(pattern: "\\b([A-Za-z-]+)=", token: .type, captureGroup: 1)
            ]),
            "css": Grammar(rules: [
                Rule(pattern: "/\\*[\\s\\S]*?\\*/", token: .comment),
                Rule(pattern: doubleQuoted, token: .string),
                Rule(pattern: singleQuoted, token: .string),
                Rule(pattern: "([-a-zA-Z]+)\\s*:", token: .keyword, captureGroup: 1),
                Rule(pattern: "([.#][-_a-zA-Z][-\\w]*)", token: .type, captureGroup: 1),
                Rule(pattern: "\\b\\d+(?:\\.\\d+)?(?:px|em|rem|%|vh|vw|s|ms)?\\b", token: .number)
            ])
        ]
    }
}
