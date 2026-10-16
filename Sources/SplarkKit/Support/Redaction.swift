/// Shortens secrets for logs and descriptions: enough to tell tokens apart, never enough to use one.
public enum Redact {
    public static func token(_ token: String?) -> String {
        guard let token else { return "nil" }
        return token.count > 12 ? "\(token.prefix(9))…\(token.suffix(4))" : "…"
    }
}
