public struct FileClassification: Sendable, Equatable {
    public let category: FileCategory
    public let recommendedSkip: Bool

    public init(category: FileCategory, recommendedSkip: Bool) {
        self.category = category
        self.recommendedSkip = recommendedSkip
    }
}
