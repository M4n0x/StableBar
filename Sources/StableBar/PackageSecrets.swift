import Foundation
import Security

func packageSecret(_ account: String) -> String {
    var data: CFTypeRef?
    let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: "StableBar", kSecAttrAccount: account,
                 kSecReturnData: true] as CFDictionary
    guard SecItemCopyMatching(query, &data) == errSecSuccess else { return "" }
    return String(decoding: data as! Data, as: UTF8.self)
}

func savePackageSecret(_ value: String, account: String) throws {
    let item = [kSecClass: kSecClassGenericPassword, kSecAttrService: "StableBar", kSecAttrAccount: account] as [CFString: Any]
    SecItemDelete(item as CFDictionary)
    guard !value.isEmpty else { return }
    let status = SecItemAdd(item.merging([kSecValueData: Data(value.utf8)]) { $1 } as CFDictionary, nil)
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
}
