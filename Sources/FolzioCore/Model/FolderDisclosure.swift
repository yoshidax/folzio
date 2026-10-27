public enum FolderDisclosure {
    public enum Toggle: Sendable, Equatable {
        case expand
        case collapse
        case none
    }

    public static func doubleClickToggle(isExpandable: Bool, isExpanded: Bool) -> Toggle {
        if isExpanded {
            return .collapse
        }
        return isExpandable ? .expand : .none
    }
}
