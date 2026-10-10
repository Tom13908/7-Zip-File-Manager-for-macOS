// 界面文案查表。
//
// 键就是 S 里那条英文原文（用词与 Windows 版 7-Zip 的资源脚本对齐），
// 译文放在 App 包里的 <语言>.lproj/Localizable.strings，由 tools/mkl10n.py 生成。
//
// 语言由系统决定：bundle 里有哪些 .lproj、当前语言挑哪一份，都是 AppKit 说了算。
// Finder 右键菜单里的服务条目走的是同一套 bundle 本地化
// （<语言>.lproj/ServicesMenu.strings），所以两边永远落在同一种语言上。
//
// 查不到就原样返回英文 —— 漏一条译文只会看到英文，不会看到空串或者键名。

import Foundation

/// 查表取当前语言的文案。
func L(_ key: String) -> String {
    L(key, key)
}

/// 查表，缺失时用给的英文兜底。给多行长文案用（键名不好直接写成那段文本）。
func L(_ key: String, _ fallback: String) -> String {
    guard !key.isEmpty else { return key }
    return Bundle.main.localizedString(forKey: key, value: fallback, table: "Localizable")
}

/// 查其它表（目前只有 Finder 服务菜单用的 ServicesMenu）。
func L(_ key: String, table: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: table)
}

/// 当前界面语言，给自检用：`7-Zip File Manager --lang` 之类的通路读它。
enum CurrentLanguage {
    /// bundle 真正挑中的那一份 .lproj，没有就是 "en"
    static var identifier: String {
        let main = Bundle.main
        guard let first = main.preferredLocalizations.first else { return "en" }
        return first
    }

    /// bundle 里带进来的全部语言（构建时由 mkl10n.py 铺进去）。
    /// Info.plist 的 CFBundleLocalizations 和 Resources 下的 .lproj 是两处声明，
    /// Foundation 会把它们合并后各报一遍，所以这里去重。
    static var available: [String] {
        Array(Set(Bundle.main.localizations.filter { $0 != "Base" })).sorted()
    }

    /// bundle 里那份 .strings 的全部键。把每个键都问一遍，就知道文案实际落到了
    /// 哪种语言上 —— 只给自检用，正常运行不看。
    static func keys(inTable table: String) -> [String] {
        guard let path = Bundle.main.path(forResource: table, ofType: "strings"),
              let d = NSDictionary(contentsOfFile: path) as? [String: String] else { return [] }
        return d.keys.sorted()
    }
}
