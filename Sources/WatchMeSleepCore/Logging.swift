import os

public extension Logger {
    /// One subsystem for every log line: /usr/bin/log stream --predicate
    /// 'subsystem == "com.wiltodelta.watchmesleep"'.
    static func app(_ category: String) -> Logger {
        Logger(subsystem: "com.wiltodelta.watchmesleep", category: category)
    }
}
