import Foundation

struct OpenAICompatibleProfile: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var baseURL: String

    init(id: String = UUID().uuidString, name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}
